import os
import urllib.parse
import logging
import json
from flask import Flask, request, send_file, abort, jsonify
from utils.helpers import read_text_file,load_config
from core.logger import setup_logger
from core.tts_engine import TTSEngine
from flask_cors import CORS  
from cachetools import TTLCache  

# 初始化日志
logger = setup_logger('tts_proxy.api', logging.INFO)

def create_app(config):
    """创建Flask应用
    
    Args:
        config: 配置字典
        
    Returns:
        Flask: Flask应用实例
    """
    app = Flask("tts_proxy_app")
    tts_engine = TTSEngine(config)
    
    # 初始化缓存（参数顺序敏感）
    raw_request_cache = TTLCache(maxsize=1024, ttl=3)  # 3秒缓存
    
    # 从YAML加载配置
    frontend_config = config.get('frontend_config', {})
    allowed_params = config.get('tts', {}).get('allowed_params', [])
    
    # CORS配置
    CORS(app,
         origins=config.get('cors', {}).get('origins', '*'),
         methods=config.get('cors', {}).get('methods', ['GET', 'POST', 'PUT']),
         allow_headers=config.get('cors', {}).get('allow_headers', ['Content-Type', 'Authorization']),
         max_age=config.get('cors', {}).get('max_age', 86400)
    )
        
    # 获取允许的参数列表，如果配置中没有则使用默认列表
    allowed_params = config.get('tts', {}).get('allowed_params', ['prompt_audio', 'prompt_text', 'text', 'text_file', 'gender', 'pitch', 'speed', 'emotion'])
    
    # 在 create_app 函数内添加以下路由（建议放在现有 /api/config 路由附近）
    
    @app.route('/config', methods=['GET'])
    def get_server_config():
        """获取服务端基础配置（新增接口）"""
        return jsonify({
            "server": {
                "host": config['local'].get('host', '127.0.0.1'),  # 从配置读取
                "port": config['local']['port'],  # **核心修改：暴露端口号**
                "api_base": "/api"  # 统一API前缀
            },
            "tts_endpoint": "/tts"  # TTS服务端点
        })
    
    @app.route('/api/config', methods=['GET'])
    def get_config():
        """获取有序前端配置"""
        structured = {
            'pitch': [{'display': o['display'], 'value': o['value']} 
                    for o in frontend_config['pitch']['options']],
            'speed': [{'display': o['display'], 'value': o['value']} 
                    for o in frontend_config['speed']['options']],
            'emotion': [{'display': o['display'], 'value': o['value']} 
                      for o in frontend_config['emotion']['options']],
            'server_config_url': '/config'  # 告知前端如何获取服务端配置
        }
        return jsonify(structured)
        
    @app.route('/api/files/<file_type>', methods=['GET'])
    def list_files(file_type):
        """列出指定类型的文件"""
        try:
            if file_type == 'prompt_audio':
                dir_path = config['local']['local_prompt_audio_path']
            elif file_type == 'text_file':
                dir_path = config['local']['local_text_file_path']
            elif file_type == 'prompt_text':
                dir_path = config['local']['local_prompt_text_path']
            else:
                return jsonify({"error": "无效的文件类型"}), 400
                
            if os.path.exists(dir_path):
                # 只列出文件，不包括目录
                files = [f for f in os.listdir(dir_path) 
                       if os.path.isfile(os.path.join(dir_path, f))]
                return jsonify({"files": files})
            else:
                return jsonify({"error": f"目录不存在: {dir_path}"}), 404
        except Exception as e:
            logger.error(f"列出文件失败: {e}")
            return jsonify({"error": str(e)}), 500
    
    @app.route('/tts', methods=['GET'])
    def tts_proxy():
        """处理TTS请求（立即拦截）"""
        # 生成原始请求指纹（包含所有参数）
        raw_params = sorted(request.args.items(multi=False))  # 获取原始参数并排序
        cache_key = json.dumps(raw_params, ensure_ascii=False)
        
        # 立即检查缓存
        if raw_request_cache.get(cache_key):
            logger.warning(f"快速拦截重复请求: {cache_key}")
            abort(429, description="重复请求被拦截，请3s后再试。")
            
        # 立即写入缓存
        raw_request_cache[cache_key] = True
        
        # 收集所有允许的参数
        params = {}
        for param in allowed_params:
            value = request.args.get(param)
            if value:
                # URL解码参数值
                value = urllib.parse.unquote(value)
                params[param] = value
                     
        # 记录原始请求
        logger.info(f"收到TTS请求: {dict(request.args)}")
        
        # 必须提供语音文本参数或语音文本文件参数
        if 'text' not in params and 'text_file' not in params:
            logger.error("请求缺少必要的文本参数")
            abort(400, description="必须提供text或text_file参数")
        
        # 必须通过提示音频或者角色性别
        if 'prompt_audio' not in params and 'gender' not in params:
            logger.error("请求缺少必要的声音参数")
            abort(400, description="必须提供prompt_audio或gender参数")

        # 检查提示音频参数
        if 'prompt_audio' in params:
            prompt_audio = params['prompt_audio']
            base_name = os.path.splitext(prompt_audio)[0]
            prompt_text_dir = config['local']['local_prompt_text_path']
            
            if not os.path.exists(prompt_text_dir):
                logger.error("提示文本目录不存在")
            else:
                # 情况1：只有提示音频，没有提示文本
                if 'prompt_text' not in params:
                    found = False
                    for text_file in os.listdir(prompt_text_dir):
                        text_base_name = os.path.splitext(text_file)[0]
                        if text_base_name == base_name:
                            text_file_path = os.path.join(prompt_text_dir, text_file)
                            content = read_text_file(text_file_path)
                            if content is not None:
                                params['prompt_text'] = content
                                logger.info(f"从文件加载提示文本: '{text_file}' -> '{content}'")
                                found = True
                                break
                    if not found:
                        logger.info(f"未找到匹配的提示文本文件: {base_name}")
                
                # 情况2：同时存在提示音频和提示文本
                else:
                    prompt_text_value = params['prompt_text']
                    # 检查是否为.txt文件名
                    if isinstance(prompt_text_value, str) and prompt_text_value.lower().endswith('.txt'):
                        text_file_path = os.path.join(prompt_text_dir, prompt_text_value)
                        if os.path.isfile(text_file_path):
                            content = read_text_file(text_file_path)
                            if content is not None:
                                params['prompt_text'] = content
                                logger.info(f"从文件加载提示文本: '{prompt_text_value}' -> '{content}'")
                            else:
                                logger.error(f"提示文本文件读取失败: {text_file_path}")
                        else:
                            logger.error(f"提示文本文件不存在: {text_file_path}")

        # 提交任务并等待结果
        result_event, hash_value = tts_engine.submit_task(params)
        result_event.wait()
        # 检查结果
        if result_event.result:
            logger.info(f"返回生成的音频文件: {result_event.result}")
            return send_file(result_event.result, mimetype='audio/wav')
        else:
            logger.error("音频生成失败")
            abort(500, description="音频生成失败")

    @app.route('/')
    def serve_index():
        index_path = os.path.join(app.root_path, 'index.html')
        return send_file(index_path)
        
    @app.route('/allowed_params', methods=['GET'])
    def prompt_list():
        """获取允许的参数列表"""
        return {
            "allowed_params": allowed_params
        }
    
    @app.errorhandler(400)
    def bad_request(e):
        return {"error": str(e)}, 400
    
    @app.errorhandler(500)
    def server_error(e):
        return {"error": str(e)}, 500
        
    # 新增429错误处理
    @app.errorhandler(429)
    def too_many_requests(e):
        return jsonify({"error": str(e)}), 429
    
    return app
