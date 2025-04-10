from logger import setup_logger
import os
import hashlib
import struct
import urllib.parse
from threading import Lock
from concurrent.futures import ThreadPoolExecutor
from flask import Flask, request, Response, send_file, current_app
import httpx
import logging
import time
import traceback
import argparse

# 欢迎页面
def show_welcome():
    print("\033[38;5;213m")  # 使用柔和的品红色
    print("  ╭"+"─"*64+"╮")
    print("  │ \033[1;38;5;231m🦄 \033[38;5;219mTermux Flow Spark-TTS Server  \033[0;38;5;213mv3.0.0"+ " "*24 +"│")
    print("  ├"+"─"*64+"┤")
    print("  │ \033[38;5;219m✦ 数据流向示意图：" + "━"*40 + "━━━┓ \033[38;5;213m│")
    print("  │ \033[38;5;225m   🎼 Spark-TTS → 🦊 Proxy Server → 📦 Cache →  🌸 SillyTevan\033[38;5;213m  │")
    print("  │ \033[38;5;219m  ┗" + "━"*55 + "━━   \033[38;5;213m│")
    print("  ├"+"─"*64 +"┤")
    print("  │ \033[38;5;226m📂 存储规则：" + " "*47 + "\033[38;5;213m   │")
    print("  │ \033[38;5;226m├─\033[38;5;228m 1. 音频将流式传输并保存到 \033[3m本地 \033[0;38;5;228m文件 "+ " "*24 +"\033[38;5;213m│")
    print("  │ \033[38;5;226m├─\033[38;5;228m 2. data文件夹数据将自动上传至 \033[3m服务器\033[0;38;5;228m 同名文件夹"+ " "*13 +"\033[38;5;213m│")
    print("  │ \033[38;5;226m└─\033[38;5;228m 3. data文件夹没有的数据将删除\033[3m 服务器\033[0;38;5;228m 中多的数据"+ " "*13 +"\033[38;5;213m│") 
    print("  ├"+"─"*64+"┤")
    print("  │ \033[38;5;153m⚙️ 其他信息：" + " "*51+ "\033[38;5;213m│")
    print(f"  │ \033[38;5;153m◉ 存储目录：\033[0;38;5;195m ./cache "+ " "*37 +"\033[38;5;213m     │")
    print("  │ \033[38;5;153m◉ 开源协议：\033[0;38;5;195m GPL-2.0 license "+ " "*33  +" \033[38;5;213m│")
    print("  ├"+"─"*64+"┤")
    print("  │ \033[38;5;226m🏷️  前端：\033[38;5;228m@DeepSeek R1 @云中鹿🦌\033[38;5;213m┃ \033[38;5;153m🐾 Dsicord：\033[38;5;159m@yunzhonglu_224690\033[0;38;5;213m│") 
    print("  ├"+"─"*64+"┤")
    print("  │ \033[38;5;226m📇 后端：\033[38;5;228m@Claude 3.7  @云中鹿🦌\033[38;5;213m┃ \033[38;5;153m🐧 QQ：\033[38;5;159m@1802141774\033[38;5;159m            \033[0;38;5;213m│")
    print("  ╰"+"─"*64+"╯\033[0m")
    print("\n\033[38;5;218m[系统初始化] 正在启动Spark-TTS反代理服务...\033[0m")

# 初始化日志
logger = setup_logger('tts_proxy.main', logging.INFO)

# 初始化应用
app = Flask(__name__)

# 配置参数
cache_dir = 'cache'
os.makedirs(cache_dir, exist_ok=True)
cache_locks = {}
executor = ThreadPoolExecutor(max_workers=4)
timeout_config = httpx.Timeout(
    connect=10.0,
    read=300.0,
    write=10.0,
    pool=10.0
)

def generate_hash(params):
    """优化后的快速哈希函数"""
    return hashlib.md5(
        f"{params.get('name','')}|{params.get('text','')}".encode('utf-8')
    ).hexdigest()

def create_wav_header(data_size, sample_rate=16000, bits_per_sample=16, channels=1):
    """生成完整的WAV文件头"""
    byte_rate = sample_rate * channels * bits_per_sample // 8
    block_align = channels * bits_per_sample // 8

    return struct.pack(
        '<4sI4s4sIHHIIHH4sI',
        b'RIFF',
        data_size + 36,
        b'WAVE',
        b'fmt ',
        16,
        1,
        channels,
        sample_rate,
        byte_rate,
        block_align,
        bits_per_sample,
        b'data',
        data_size
    )

def async_save_cache(cache_path, data):
    """线程池异步保存缓存"""
    try:
        # 增加调试信息
        logger.debug(f"准备保存缓存，数据长度: {len(data)}字节")
        logger.debug(f"缓存文件头部十六进制: {data[:20].hex()}")
        
        # 确保目录存在
        os.makedirs(os.path.dirname(cache_path), exist_ok=True)
        
        with open(cache_path, 'wb') as f:
            f.write(data)
        logger.info(f"缓存保存成功: {cache_path}")
    except Exception as e:
        logger.error(f"缓存保存失败: {str(e)}")
        # 添加详细的错误堆栈
        logger.error(f"错误详情: {traceback.format_exc()}")

def validate_audio_data(data):
    """检查音频数据是否为空"""
    if not data or len(data) == 0:
        logger.warning("收到空的音频数据")
        return False
    
    logger.debug(f"音频数据大小: {len(data)}字节")
    return True

@app.route('/tts', methods=['GET'])
def tts_proxy():
    """核心处理逻辑"""
    start_time = time.time()
    
    try:
        # 解码URL参数
        raw_params = {k: urllib.parse.unquote(v) for k, v in request.args.to_dict().items()}
        params = {
            'name': raw_params.get('name', ''),
            'text': raw_params.get('text', ''),
            'temperature': raw_params.get('temperature', '0.8'),
            'top_p': raw_params.get('top_p', '0.95'),
            'top_k': raw_params.get('top_k', '50'),
            'max_tokens': raw_params.get('max_tokens', '4096')
        }

        # 更多调试信息
        logger.debug(f"请求参数: name={params['name']}, text长度={len(params['text'])}")

        # 生成缓存标识
        hash_start = time.time()
        cache_name = f"{params['name']}_{generate_hash(params)}.wav"
        cache_path = os.path.join(cache_dir, cache_name)
        logger.debug(f"哈希计算耗时: {(time.time()-hash_start)*1000:.2f}ms，缓存路径: {cache_path}")

        # 首次快速缓存检查
        if os.path.exists(cache_path):
            logger.info(f"缓存命中: {cache_name}")
            return send_file(cache_path, mimetype='audio/wav')

        # 获取文件级锁
        file_lock = cache_locks.setdefault(cache_name, Lock())
        
        with file_lock:
            # 双重检查锁定
            if os.path.exists(cache_path):
                logger.info(f"缓存命中(锁释放后): {cache_name}")
                return send_file(cache_path, mimetype='audio/wav')

            # 构造后端请求
            backend_url = current_app.config['BACKEND_URL']
            headers = {'Content-Type': 'application/json'}
            payload = {
                "name": params['name'],
                "text": params['text'],
                "temperature": float(params['temperature']),
                "top_p": float(params['top_p']),
                "top_k": int(params['top_k']),
                "max_tokens": int(params['max_tokens']),
                "stream": True
            }

            logger.debug(f"准备连接后端服务: {backend_url}")
            collected_chunks = []

            def generate_stream():
                """流式响应生成器"""
                try:
                    logger.debug("开始流式请求")
                    with httpx.stream(
                        'POST',
                        backend_url,
                        json=payload,
                        headers=headers,
                        timeout=timeout_config
                    ) as response:
                        response.raise_for_status()
                        logger.debug(f"后端服务响应状态码: {response.status_code}")
                        header_sent = False
                        data_buffer = bytearray()

                        for chunk in response.iter_bytes():
                            if not isinstance(chunk, bytes):
                                chunk = bytes(chunk)
                            
                            if chunk:
                                collected_chunks.append(chunk)
                                
                                # 收到数据块
                                
                                # 第一个分块时，先发送WAV头
                                if not header_sent:
                                    logger.debug(f"收到第一个数据块，大小: {len(chunk)}字节")
                                    # 发送一个临时的WAV头
                                    yield create_wav_header(0)
                                    header_sent = True
                                
                                # 发送原始音频数据
                                yield chunk

                        # 流结束后处理
                        logger.debug(f"流式响应完成，共收到{len(collected_chunks)}个数据块")
                        
                        if collected_chunks:
                            # 直接拼接所有收到的数据块
                            audio_data = b''.join(collected_chunks)
                            logger.debug(f"总数据大小: {len(audio_data)}字节")
                            
                            if len(audio_data) > 0:
                                # 已确认收到的是纯音频数据，直接添加WAV头
                                wav_file = create_wav_header(len(audio_data)) + audio_data
                                logger.debug(f"添加WAV头部后文件大小: {len(wav_file)}字节")
                                executor.submit(async_save_cache, cache_path, wav_file)
                            else:
                                logger.error("收到空数据，放弃缓存")

                except httpx.TimeoutException as e:
                    logger.error(f"后端服务超时: {str(e)}")
                    
                except Exception as e:
                    logger.error(f"流式请求异常: {str(e)}")
                    logger.error(f"异常详情: {traceback.format_exc()}")
                    
                finally:
                    if not collected_chunks:
                        logger.warning("未收集到任何数据")
                        

            return Response(generate_stream(), mimetype='audio/wav')

    except Exception as e:
        logger.error(f"全局异常: {str(e)}")
        logger.error(f"异常详情: {traceback.format_exc()}")
        
    finally:
        logger.info(f"请求处理耗时: {(time.time()-start_time)*1000:.2f}ms")

if __name__ == '__main__':
    show_welcome()
    
    # 解析命令行参数
    parser = argparse.ArgumentParser(description='Spark-TTS代理服务')
    parser.add_argument('--backend_url', 
                      default='http://localhost:8002/speak',
                      help='后端TTS服务地址（默认：http://localhost:8002/speak）')
    parser.add_argument('--port',
                      type=int,
                      default=5000,
                      help='服务监听端口（默认：5000）')
    args = parser.parse_args()
    
    # 修改Flask运行方式，使用安静模式
    import sys
    cli = sys.modules['flask.cli']
    cli.show_server_banner = lambda *args, **kwargs: None
    
    # 配置Flask应用
    app.config['BACKEND_URL'] = args.backend_url
    
    # 启动应用
    logger.debug(f"后端服务地址: {app.config['BACKEND_URL']}")
    logger.info(f"服务器将监听 http://localhost:{args.port}")
    logger.info(f"请求链接示例 http://localhost:{args.port}/tts?name=后羿&text=周日被我射熄火了，所以今天是周一！")
    app.run(host='0.0.0.0', port=args.port, threaded=True)
