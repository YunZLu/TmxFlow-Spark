import os
import hashlib
import json
from core.logger import setup_logger
import logging

# 初始化日志
logger = setup_logger('tts_proxy.cache', logging.DEBUG)

class CacheManager:
    def __init__(self, cache_dir):
        """初始化缓存管理器
        
        Args:
            cache_dir: 缓存目录
        """
        self.cache_dir = cache_dir
        # 创建缓存目录
        os.makedirs(self.cache_dir, exist_ok=True)
    
    def generate_hash(self, params):
        """根据请求参数生成唯一哈希值
        
        Args:
            params: 请求参数字典
            
        Returns:
            str: 哈希值
        """
        param_str = json.dumps(params, sort_keys=True)
        hash_value = hashlib.md5(param_str.encode('utf-8')).hexdigest()
        logger.debug(f"为参数生成哈希值: {hash_value}")
        return hash_value
    
    def get_cache_filename(self, params, hash_value):
        """生成缓存文件名
        
        Args:
            params: 请求参数字典
            hash_value: 哈希值
            
        Returns:
            str: 缓存文件名
        """
        if 'prompt_audio' in params and params['prompt_audio']:
            prompt_name = os.path.splitext(params['prompt_audio'])[0]  # 移除可能的.wav扩展名
            if not prompt_name.endswith('.wav'):
                prompt_name = prompt_name.replace('.', '_')  # 处理文件名中的点
            filename = f"{prompt_name}_{hash_value}.wav"
        elif 'text_file' in params and params['text_file']:
            try:
                # 构造文件路径并读取内容
                file_path = os.path.join('text_file', params['text_file'])
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read().strip()
                # 取前8个字符作为前缀
                text_prefix = content[:8]
                filename = f"{text_prefix}_{hash_value}.wav"
            except Exception as e:
                logger.error(f"读取text_file文件失败：{e}")
                # 失败时回退到默认文件名
                filename = f"tts_{hash_value}.wav"
        elif 'text' in params and params['text']:
            # 取文本前8个字符(考虑中文)
            text_prefix = params['text'][:8]
            filename = f"{text_prefix}_{hash_value}.wav"
        else:
            filename = f"tts_{hash_value}.wav"
            
        logger.debug(f"生成缓存文件名: {filename}")
        return filename
    
    def get_cache_path(self, params, hash_value=None):
        """获取缓存文件路径
        
        Args:
            params: 请求参数字典
            hash_value: 可选的哈希值，如果未提供将自动生成
            
        Returns:
            str: 缓存文件路径
        """
        if hash_value is None:
            hash_value = self.generate_hash(params)
            
        filename = self.get_cache_filename(params, hash_value)
        cache_path = os.path.join(self.cache_dir, filename)
        logger.debug(f"缓存文件路径: {cache_path}")
        return cache_path
    
    def exists(self, params, hash_value=None):
        """检查缓存是否存在
        
        Args:
            params: 请求参数字典
            hash_value: 可选的哈希值，如果未提供将自动生成
            
        Returns:
            bool: 缓存存在返回True，否则返回False
        """
        cache_path = self.get_cache_path(params, hash_value)
        exists = os.path.exists(cache_path)
        if exists:
            logger.info(f"找到缓存文件: {cache_path}")
        else:
            logger.debug(f"缓存文件不存在: {cache_path}")
        return exists
