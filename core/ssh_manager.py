import os
import paramiko
import re
import logging
from core.logger import setup_logger
import socket

# 关闭 Paramiko 的全部日志输出
paramiko_logger = logging.getLogger("paramiko")
paramiko_logger.setLevel(logging.CRITICAL)  # 只允许 CRITICAL 级别日志
paramiko_logger.propagate = False  # 阻止日志传递到根日志器

# 初始化日志
logger = setup_logger('tts_proxy.ssh', logging.DEBUG)

class SSHManager:
    def __init__(self, config):
        """初始化SSH管理器
        
        Args:
            config: SSH配置字典
        """
        self.config = config
        self.remote_python_path = "python"  # 默认Python路径
        self.client = None
    
    def connect(self):
        """连接到远程SSH服务器
        
        Returns:
            paramiko.SSHClient: 连接成功返回客户端，失败返回None
        """
        if self.client and self.client.get_transport() and self.client.get_transport().is_active():
            logger.debug("复用已有的SSH连接")
            return self.client
            
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        
        try:
            client.connect(
                hostname=self.config['ssh']['host'],
                port=self.config['ssh']['port'],
                username=self.config['ssh']['username'],
                password=self.config['ssh']['password'],
                timeout=10
            )
            logger.info("SSH连接成功")
            self.client = client
            return client
        except paramiko.ssh_exception.SSHException as e:
            logger.error(f"SSH协议错误，请检查配置或网络: {str(e)}")
        except socket.timeout:
            logger.error("连接超时，请检查网络或服务器状态")
        except socket.error as e:
            logger.error(f"网络连接失败: 请确认地址和端口是否正确 (错误代码: {e.errno})")
        except Exception as e:
            logger.error(f"未知错误，请联系管理员 (错误代码: {str(e)})")
        return None
    
    def close(self):
        """关闭SSH连接"""
        if self.client:
            self.client.close()
            self.client = None
            logger.debug("SSH连接已关闭")
    
    def get_remote_python_path(self, conda_env="sparktts"):
        """自动获取远程服务器上conda环境的Python路径
        
        Args:
            conda_env: Conda环境名称
            
        Returns:
            str: Python解释器路径
        """
        if not self.client:
            logger.error("未建立SSH连接，无法获取远程Python路径")
            return "python"
            
        try:
            # 尝试获取conda环境中的Python路径
            commands_to_try = [
                # 尝试使用已激活的环境
                f"which python",
                # 尝试在bash中查找
                f"bash -c 'which python'",
                # 尝试先找到conda命令
                "which conda && conda info --base",
            ]
            
            for cmd in commands_to_try:
                logger.debug(f"尝试命令: {cmd}")
                stdin, stdout, stderr = self.client.exec_command(cmd)
                result = stdout.read().decode().strip()
                error = stderr.read().decode().strip()
                
                if result and not error:
                    logger.debug(f"命令返回: {result}")
                    
                    # 如果找到了conda base路径
                    if "conda info" in cmd:
                        conda_base = result
                        logger.debug(f"找到conda base路径: {conda_base}")
                        
                        # 尝试使用conda base激活环境
                        cmd = f"source {conda_base}/etc/profile.d/conda.sh && conda activate {conda_env} && which python"
                        logger.debug(f"尝试激活conda环境: {cmd}")
                        stdin, stdout, stderr = self.client.exec_command(cmd)
                        python_path = stdout.read().decode().strip()
                        
                        if python_path:
                            logger.info(f"找到conda环境Python路径: {python_path}")
                            self.remote_python_path = python_path
                            return python_path
                    else:
                        # 直接找到的python路径
                        logger.info(f"找到系统Python路径: {result}")
                        self.remote_python_path = result
                        return result
            
            # 如果上面失败，尝试直接查找可能的路径
            potential_paths = [
                f"/root/miniconda3/envs/{conda_env}/bin/python",
                f"/home/$(whoami)/miniconda3/envs/{conda_env}/bin/python",
                f"/opt/conda/envs/{conda_env}/bin/python",
                f"/usr/bin/python3"
            ]
            
            for path in potential_paths:
                cmd = f"[ -f {path} ] && echo {path} || echo ''"
                logger.debug(f"检查可能的Python路径: {path}")
                stdin, stdout, stderr = self.client.exec_command(cmd)
                result = stdout.read().decode().strip()
                if result:
                    logger.info(f"找到备选Python路径: {result}")
                    self.remote_python_path = result
                    return result
            
            # 如果都失败，则返回默认的python命令
            logger.warning("无法自动检测Python路径，将使用默认的'python'命令")
            return "python"
        except Exception as e:
            logger.error(f"获取远程Python路径失败: {e}")
            return "python"  # 默认回退到'python'命令
    
    def list_remote_files(self, directory):
        """列出远程目录中的文件
        
        Args:
            directory: 远程目录路径
            
        Returns:
            list: 文件名列表
        """
        if not self.client:
            logger.error("未建立SSH连接，无法列出远程文件")
            return []
            
        try:
            cmd = f"ls -la {directory}"
            logger.debug(f"执行命令列出目录: {cmd}")
            stdin, stdout, stderr = self.client.exec_command(cmd)
            output = stdout.read().decode()
            error = stderr.read().decode()
            
            if error and "No such file or directory" in error:
                logger.warning(f"远程目录不存在: {directory}")
                return []
            elif error:
                logger.error(f"列出远程目录失败: {error}")
                return []
            
            logger.debug(f"远程目录 {directory} 内容:\n{output}")
            
            # 从输出中提取文件名
            files = []
            for line in output.splitlines()[1:]:  # 跳过第一行 total N
                parts = line.split()
                if len(parts) >= 9:  # 至少有9列
                    filename = ' '.join(parts[8:])
                    if filename not in ['.', '..']:
                        files.append(filename)
            
            return files
        except Exception as e:
            logger.error(f"列出远程目录异常: {e}")
            return []
    
    def check_remote_file_exists(self, filepath):
        """检查远程文件是否存在
        
        Args:
            filepath: 远程文件路径
            
        Returns:
            bool: 文件存在返回True，否则返回False
        """
        if not self.client:
            logger.error("未建立SSH连接，无法检查远程文件")
            return False
            
        try:
            cmd = f"[ -f \"{filepath}\" ] && echo 'exists' || echo 'not exists'"
            logger.debug(f"执行命令检查文件: {cmd}")
            stdin, stdout, stderr = self.client.exec_command(cmd)
            result = stdout.read().decode().strip()
            
            # 获取文件所在目录
            directory = os.path.dirname(filepath)
            logger.debug(f"检查远程目录 {directory} 中的文件")
            
            # 列出目录中的文件，帮助调试
            files = self.list_remote_files(directory)
            logger.debug(f"远程目录中的文件: {files}")
            
            return result == 'exists'
        except Exception as e:
            logger.error(f"检查远程文件失败: {e}")
            return False
    
    def execute_command(self, command, real_time_log=False):
        """执行远程命令
        
        Args:
            command: 要执行的命令
            real_time_log: 是否实时输出日志
            
        Returns:
            tuple: (成功标志, 输出, 错误)
        """
        if not self.client:
            logger.error("未建立SSH连接，无法执行命令")
            return False, "", "未建立SSH连接"
            
        try:
            logger.debug(f"执行远程命令: {command}")
            
            if real_time_log and logger.level <= logging.DEBUG:
                # 创建一个新的会话通道，用于实时获取输出
                channel = self.client.get_transport().open_session()
                channel.get_pty()  # 获取伪终端
                channel.exec_command(command)
                
                output_lines = []
                error_lines = []
                
                # 持续读取输出，直到命令执行完毕
                while True:
                    # 处理标准输出
                    if channel.recv_ready():
                        line = channel.recv(4096).decode('utf-8')
                        if line:
                            output_lines.append(line)
                            # 分析日志级别并相应地打印
                            if "INFO" in line:
                                logger.info(f"[远程INFO] {line.rstrip()}")
                            elif "WARNING" in line or "WARN" in line:
                                logger.warning(f"[远程WARNING] {line.rstrip()}")
                            elif "ERROR" in line or "CRITICAL" in line:
                                logger.error(f"[远程ERROR] {line.rstrip()}")
                            elif "DEBUG" in line:
                                logger.debug(f"[远程DEBUG] {line.rstrip()}")
                            else:
                                logger.debug(f"[远程输出] {line.rstrip()}")
                    
                    # 处理标准错误
                    if channel.recv_stderr_ready():
                        line = channel.recv_stderr(4096).decode('utf-8')
                        if line:
                            error_lines.append(line)
                            # 对于stderr，我们通常视为错误
                            if not line.strip():  # 忽略空行
                                continue
                            if "WARNING" in line or "WARN" in line:
                                logger.warning(f"[远程错误] {line.rstrip()}")
                            else:
                                logger.error(f"[远程错误] {line.rstrip()}")
                    
                    if channel.exit_status_ready():
                        # 获取剩余的输出
                        while channel.recv_ready():
                            line = channel.recv(4096).decode('utf-8')
                            if line:
                                output_lines.append(line)
                        
                        while channel.recv_stderr_ready():
                            line = channel.recv_stderr(4096).decode('utf-8')
                            if line:
                                error_lines.append(line)
                        
                        exit_status = channel.recv_exit_status()
                        channel.close()
                        
                        output = ''.join(output_lines)
                        error = ''.join(error_lines)
                        
                        success = exit_status == 0
                        
                        # 避免重复记录详细错误日志，只显示退出状态
                        if not success:
                            logger.error(f"命令执行失败，退出状态码: {exit_status}")
                        
                        return success, output, error
            else:
                # 原来的非实时日志方式
                stdin, stdout, stderr = self.client.exec_command(command)
                output = stdout.read().decode()
                error = stderr.read().decode()
                
                exit_status = stdout.channel.recv_exit_status()
                success = exit_status == 0
                
                if not success:
                    logger.error(f"命令执行错误，退出状态码: {exit_status}")
                    if logger.level <= logging.DEBUG:
                        logger.debug(f"错误详情: {error}")
                else:
                    logger.info("远程命令执行成功")
                    if logger.level <= logging.DEBUG:
                        logger.debug(f"命令输出: {output}")
                    
                return success, output, error
                
        except Exception as e:
            logger.error(f"执行命令异常: {e}")
            return False, "", str(e)

    
    def download_file(self, remote_path, local_path):
        """下载远程文件到本地
        
        Args:
            remote_path: 远程文件路径
            local_path: 本地文件路径
            
        Returns:
            bool: 下载成功返回True，失败返回False
        """
        if not self.client:
            logger.error("未建立SSH连接，无法下载文件")
            return False
            
        try:
            sftp = self.client.open_sftp()
            logger.debug(f"下载文件 {remote_path} -> {local_path}")
            sftp.get(remote_path, local_path)
            sftp.close()
            logger.info(f"文件下载成功: {local_path}")
            return True
        except Exception as e:
            logger.error(f"下载文件失败: {e}")
            return False
    
    def remove_remote_file(self, remote_path):
        """删除远程文件
        
        Args:
            remote_path: 远程文件路径
            
        Returns:
            bool: 删除成功返回True，失败返回False
        """
        if not self.client:
            logger.error("未建立SSH连接，无法删除文件")
            return False
            
        try:
            sftp = self.client.open_sftp()
            logger.debug(f"删除远程文件: {remote_path}")
            sftp.remove(remote_path)
            sftp.close()
            logger.info(f"远程文件删除成功: {remote_path}")
            return True
        except Exception as e:
            logger.error(f"删除远程文件失败: {e}")
            return False
