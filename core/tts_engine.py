import os
import re
import threading
import queue
import logging
from core.logger import setup_logger
from core.ssh_manager import SSHManager
from core.cache import CacheManager

# 初始化日志
logger = setup_logger('tts_proxy.tts', logging.DEBUG)

class TTSEngine:
    def __init__(self, config):
        """初始化TTS引擎
        
        Args:
            config: 配置字典
        """
        self.config = config
        self.ssh = SSHManager(config)
        self.cache = CacheManager(config['local']['cache_dir'])
        
        # 任务队列
        self.task_queue = queue.Queue()
        # 正在处理的任务数
        self.active_tasks = 0
        # 队列锁
        self.queue_lock = threading.Lock()
        
        # 启动工作线程
        self.start_worker()

    def start_worker(self):
        """启动工作线程处理队列任务"""
        worker_thread = threading.Thread(target=self._worker, daemon=True)
        worker_thread.start()
        logger.info("TTS工作线程已启动")
    
    def _worker(self):
        """工作线程处理队列中的任务"""
        while True:
            params, hash_value, result_event = self.task_queue.get()
            
            with self.queue_lock:
                self.active_tasks += 1
                logger.info(f"开始处理任务，当前活动任务数: {self.active_tasks}")
            
            try:
                result = self.process_tts_task(params, hash_value)
                result_event.result = result
            except Exception as e:
                logger.error(f"任务处理异常: {e}")
                result_event.result = None
            finally:
                with self.queue_lock:
                    self.active_tasks -= 1
                    logger.info(f"任务处理完成，当前活动任务数: {self.active_tasks}")
                
                result_event.set()
                self.task_queue.task_done()
    
    def build_tts_command(self, params):
        """构建TTS命令
        
        Args:
            params: TTS参数字典
                
        Returns:
            str: TTS命令字符串
        """
        cmd = f"cd {self.config['tts']['workdir']}; {self.ssh.remote_python_path} {self.config['tts']['command']}"
        
        for key, value in params.items():
            if value:
                # 确保文本参数用引号包裹
                if key in ['text', 'prompt_text']:
                    cmd += f' --{key} "{value}"'
                # 特殊处理prompt_audio参数
                elif key == 'prompt_audio':
                    # value此时应该已经是完整的相对路径（包含正确的扩展名）
                    cmd += f' --{key} "{value}"'
                else:
                    cmd += f' --{key} {value}'
        
        logger.debug(f"构建TTS命令: {cmd}")
        return cmd
    
    def process_tts_task(self, params, hash_value):
        """处理TTS任务
        
        Args:
            params: TTS参数字典
            hash_value: 参数哈希值
            
        Returns:
            str: 生成的音频文件路径，失败返回None
        """
        cache_path = self.cache.get_cache_path(params, hash_value)
        
        # 如果缓存存在，直接返回
        if os.path.exists(cache_path):
            logger.info(f"使用缓存: {cache_path}")
            return cache_path
        
        # 连接SSH
        ssh_client = self.ssh.connect()
        if not ssh_client:
            return None
        
        try:
            # 获取远程Python路径（如果还没有获取）
            if self.ssh.remote_python_path == "python":
                conda_env = self.config['tts'].get('conda_env', 'sparktts')
                self.ssh.remote_python_path = self.ssh.get_remote_python_path(conda_env)
                logger.info(f"将使用Python路径: {self.ssh.remote_python_path}")
            
            # 调试：列出远程TTS目录结构
            tts_dir = self.config['tts']['workdir']
            self.ssh.list_remote_files(tts_dir)
            
            # 检查提示音频文件
            if 'prompt_audio' in params:
                exists, remote_path = self._check_remote_file_exists(
                    param_name='提示音频',
                    param_value=params['prompt_audio'],
                    remote_dir=self.config['tts']['remote_prompt_audio_path'],
                    allowed_extensions=['.wav','.mp3','.ogg']
                )
                if not exists:
                    return None
                # 更新参数中的文件路径
                params['prompt_audio'] = remote_path
            
            # 检查文本文件
            if 'text_file' in params:
                exists, remote_path = self._check_remote_file_exists(
                    param_name='语音文本',
                    param_value=params['text_file'],
                    remote_dir=self.config['tts']['remote_text_file_path'],
                    allowed_extensions=['.txt']
                )
                if not exists:
                    return None
                # 更新参数中的文件路径
                params['text_file'] = remote_path
        
            # 构建并执行TTS命令
            cmd = self.build_tts_command(params)
            success, output, error = self.ssh.execute_command(cmd, real_time_log=True)
            
            if not success:
                logger.error(f"TTS命令执行失败: {cmd}")
                if error:
                    logger.error(f"服务器错误信息: {error}")
                return None
            
            # 从输出中提取生成的音频文件路径
            match = re.search(r"Generated audio file: (.+)", output)
            if not match:
                logger.error("无法从输出中找到生成的音频文件路径")
                return None
            
            output_file = match.group(1).strip()
            remote_path = output_file
            if not os.path.isabs(output_file):
                remote_path = f"{self.config['tts']['workdir']}/{output_file}"
            
            logger.debug(f"TTS生成的音频文件: {remote_path}")
            
            # 下载生成的音频文件
            if not self.ssh.download_file(remote_path, cache_path):
                return None
            
            # 删除远程音频文件
            self.ssh.remove_remote_file(remote_path)
            
            return cache_path
            
        except Exception as e:
            logger.error(f"处理TTS任务失败: {e}")
            return None
    
    def submit_task(self, params):
        """提交TTS任务
        
        Args:
            params: TTS参数字典
            
        Returns:
            tuple: (ResultEvent对象, 哈希值)
        """
        hash_value = self.cache.generate_hash(params)
        result_event = ResultEvent()
        
        # 先检查缓存
        cache_path = self.cache.get_cache_path(params, hash_value)
        if os.path.exists(cache_path):
            logger.info(f"找到缓存: {cache_path}")
            result_event.result = cache_path
            result_event.set()
            return result_event, hash_value
        
        # 添加任务到队列
        self.task_queue.put((params, hash_value, result_event))
        logger.info(f"任务已添加到队列，等待处理...")
        
        return result_event, hash_value

    def _check_remote_file_exists(self, param_name, param_value, remote_dir, allowed_extensions):
        """检查参数对应的文件是否存在于远程目录中，并返回找到的实际文件路径
    
        Args:
            param_name: 参数名称
            param_value: 参数值（文件名，可能带或不带扩展名）
            remote_dir: 远程目录路径
            allowed_extensions: 允许的文件扩展名列表
    
        Returns:
            tuple: (是否存在, 完整的远程文件相对路径)
            如果文件存在，返回(True, 相对路径)
            如果文件不存在，返回(False, None)
        """
        if not param_value:
            return False, None
    
        # 提取文件名部分（去除路径）
        filename_part = os.path.basename(param_value)
        # 获取不带扩展名的文件名
        base_name = os.path.splitext(filename_part)[0]
    
        # 获取远程目录文件列表
        tts_dir = self.config['tts']['workdir']
        remote_dir_path = f"{tts_dir}/{remote_dir}"
        logger.debug(f"检查远程目录: {remote_dir_path}")
    
        remote_files = self.ssh.list_remote_files(remote_dir_path)
        logger.debug(f"远程目录中的文件: {remote_files}")
    
        # 如果传入的文件名已经包含扩展名，且扩展名在允许列表中
        file_ext = os.path.splitext(filename_part)[1]
        if file_ext in allowed_extensions:
            full_remote_path = f"{tts_dir}/{remote_dir}/{filename_part}"
            if self.ssh.check_remote_file_exists(full_remote_path):
                logger.info(f"找到远程{param_name}文件: {full_remote_path}")
                return True, f"{remote_dir}/{filename_part}"
    
        # 检查是否存在其他允许的扩展名的文件
        for ext in allowed_extensions:
            filename = f"{base_name}{ext}"
            full_remote_path = f"{tts_dir}/{remote_dir}/{filename}"
    
            if self.ssh.check_remote_file_exists(full_remote_path):
                logger.info(f"找到远程{param_name}文件: {full_remote_path}")
                return True, f"{remote_dir}/{filename}"
    
        # 未找到匹配的文件
        logger.error(f"远程服务器上不存在{param_name}文件: {base_name} (允许的扩展名: {', '.join(allowed_extensions)})")
        return False, None
        
class ResultEvent(threading.Event):
    """带结果的事件"""
    def __init__(self):
        super().__init__()
        self.result = None
