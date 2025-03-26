import socket
import yaml
from core.logger import setup_logger
import logging

# 初始化日志
logger = setup_logger('tts_proxy.helpers', logging.INFO)

def get_local_ip():
    """获取本地IP地址
    
    Returns:
        str: 本地IP地址
    """
    try:
        # 创建一个临时连接来获取本地IP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()
        return local_ip
    except:
        # 如果失败，返回localhost
        return "127.0.0.1"

# 读取文本文件内容
def read_text_file(file_path):
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return f.read().strip()
    except Exception as e:
        logger.error(f"读取提示文本文件失败: {e}")
        return None
        
def load_config(config_path='config.yaml'):
    """加载YAML配置文件
    
    Args:
        config_path: 配置文件路径
        
    Returns:
        dict: 配置字典
    """
    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f)
        # 对每个配置项进行排序
        for category in ['pitch', 'speed', 'emotion']:
            if category in config['frontend_config']:
                config['frontend_config'][category]['options'] = sorted(
                    config['frontend_config'][category]['options'],
                    key=lambda x: x['order']
                )
        return config
    except Exception as e:
        logger.critical(f"配置文件加载失败: {e}")
        exit(1)
        
    
