import logging
import sys
import os
from datetime import datetime

class ProfessionalFormatter(logging.Formatter):
    """符合现代风格的彩色日志格式化器"""
    COLOR_SCHEME = {
        'time': '\033[38;5;245m',       # 高级灰 (时间戳)
        'module': '\033[1;37m',         # 纯白色 (模块名)
        'lineno': '\033[38;5;111m',     # 莫兰迪蓝 (行号)
        'level': {
            'DEBUG': '\033[38;5;111m',  # 浅蓝色
            'INFO': '\033[38;5;114m',   # 草木绿
            'WARNING': '\033[38;5;214m',# 落日橙
            'ERROR': '\033[38;5;203m',  # 赤陶红
            'CRITICAL': '\033[48;5;52m\033[1;37m'  # 深红底白字
        }
    }
    
    RESET = '\033[0m'

    def __init__(self, datefmt=None):
        super().__init__(datefmt=datefmt)
        self.datefmt = datefmt

    def format(self, record):
        asctime = self.formatTime(record, self.datefmt)
        level_color = self.COLOR_SCHEME['level'].get(record.levelname, self.RESET)
        message = record.getMessage()
        
        # 处理异常信息
        if record.exc_info:
            message += '\n' + self.formatException(record.exc_info)
            
        # 紧凑型级别显示（保留4字符宽度）
        level_abbr = {
            'DEBUG': 'DEBG',
            'INFO': 'INFO',
            'WARNING': 'WARN',
            'ERROR': 'ERR',
            'CRITICAL': 'CRIT'
        }.get(record.levelname, record.levelname)
        
        formatted = (
            f"{self.COLOR_SCHEME['time']}{asctime}{self.RESET} | "
            f"{level_color}{level_abbr:4}{self.RESET} | "
            f"{self.COLOR_SCHEME['module']}{record.module}:"
            f"{self.COLOR_SCHEME['lineno']}{record.lineno}{self.RESET} | "
            f"{level_color}{message}{self.RESET}"
        )
        return formatted

def setup_logger(name, level=logging.INFO):
    """配置日志记录器
    
    Args:
        name: 日志记录器名称
        level: 日志级别
    
    Returns:
        logging.Logger: 配置好的日志记录器
    """
    # 禁用 Flask 默认日志
    logging.getLogger('werkzeug').disabled = True
    logging.getLogger('flask.app').disabled = True
    
    # 创建日志目录
    log_dir = "logs"
    os.makedirs(log_dir, exist_ok=True)
    
    # 生成带时间戳的文件名
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_filename = f"app_{timestamp}.log"
    log_path = os.path.join(log_dir, log_filename)
    
    # 控制台处理器
    console_handler = logging.StreamHandler(sys.stdout)
    console_formatter = ProfessionalFormatter(datefmt='%Y-%m-%d %H:%M:%S')
    console_handler.setFormatter(console_formatter)
    
    # 文件处理器
    file_handler = logging.FileHandler(log_path)
    file_formatter = logging.Formatter(
        '[%(asctime)s] |%(levelname)8s|%(module)10s:%(lineno)4d| %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    file_handler.setFormatter(file_formatter)
    
    # 创建应用特定的日志记录器
    logger = logging.getLogger(name)
    logger.setLevel(level)
    
    # 清除可能存在的旧处理器
    for old_handler in logger.handlers:
        logger.removeHandler(old_handler)
    
    # 添加新处理器
    logger.addHandler(console_handler)
    logger.addHandler(file_handler)
    
    return logger
