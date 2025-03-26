import os
import logging
from core.logger import setup_logger

logger = setup_logger('tts_proxy.sync', logging.DEBUG)

class FileSynchronizer:
    """通用文件同步器"""
    
    def __init__(self, ssh_client, local_path, remote_path):
        """初始化同步器
        
        Args:
            ssh_client: SSH客户端实例
            local_path: 本地文件夹路径
            remote_path: 远程文件夹路径
        """
        self.ssh = ssh_client
        self.local_path = local_path
        self.remote_path = remote_path
        
        # 创建本地目录（如果不存在）
        os.makedirs(self.local_path, exist_ok=True)
    
    def sync_files(self):
        """同步文件
        
        Returns:
            bool: 同步是否成功
        """
        logger.info(f"开始同步文件...")
        logger.info(f"本地路径: {self.local_path}")
        logger.info(f"远程路径: {self.remote_path}")
        
        try:
            # 获取远程文件列表
            remote_files = self._get_remote_files()
            if remote_files is None:
                logger.error("获取远程文件列表失败")
                return False
            else:
                logger.debug(f"远程文件列表:{remote_files}")
                
            # 获取本地文件列表
            local_files = self._get_local_files()
            logger.debug(f"本地文件列表:{local_files}")
            
            # 计算需要上传、删除和更新的文件
            to_upload = []
            to_update = []
            to_delete = []
            
            # 检查需要上传和更新的文件（以本地为准）
            for local_file, local_size in local_files.items():
                if local_file not in remote_files:
                    to_upload.append(local_file)
                    logger.debug(f"文件将被上传: {local_file}")
                elif remote_files[local_file] != local_size:
                    to_update.append(local_file)
                    logger.debug(f"文件将被更新: {local_file} (本地: {local_size}字节, 远程: {remote_files[local_file]}字节)")
            
            # 检查需要删除的文件（远程有但本地没有）
            for remote_file in remote_files:
                if remote_file not in local_files:
                    to_delete.append(remote_file)
                    logger.debug(f"文件将被删除: {remote_file}")
            
            # 执行文件操作
            success = True
            
            # 上传新文件
            for file_name in to_upload:
                if not self._upload_file(file_name):
                    success = False
            
            # 更新已有文件（先删除再上传）
            for file_name in to_update:
                if not self._delete_remote_file(file_name) or not self._upload_file(file_name):
                    success = False
            
            # 删除多余文件
            for file_name in to_delete:
                if not self._delete_remote_file(file_name):
                    success = False
            
            # 输出同步统计信息
            logger.info(f"同步完成: 上传 {len(to_upload)} 个文件, 更新 {len(to_update)} 个文件, 删除 {len(to_delete)} 个文件")
            return success
            
        except Exception as e:
            logger.error(f"同步文件时发生错误: {e}")
            return False
    
    def _get_remote_files(self):
        """获取远程文件列表及大小
        
        Returns:
            dict: 文件名到文件大小的映射，失败时返回None
        """
        try:
            # 检查远程目录是否存在，如果不存在则创建
            cmd = f"if [ ! -d \"{self.remote_path}\" ]; then mkdir -p \"{self.remote_path}\"; fi"
            success, _, error = self.ssh.execute_command(cmd)
            if not success:
                logger.error(f"创建远程目录失败: {error}")
                return None
            
            # 获取远程文件列表，包含文件名和大小
            cmd = f"find \"{self.remote_path}\" -type f -exec ls -l {{}} \\;"
            success, output, error = self.ssh.execute_command(cmd)
            if not success:
                logger.error(f"获取远程文件列表失败: {error}")
                return None
            
            # 解析输出，提取文件名和大小
            files = {}
            for line in output.splitlines():
                parts = line.split()
                if len(parts) >= 5:
                    size = int(parts[4])
                    path = ' '.join(parts[8:]) if len(parts) > 8 else parts[8]
                    file_name = os.path.basename(path)
                    files[file_name] = size
            
            logger.info(f"远程文件数量: {len(files)}")
            return files
            
        except Exception as e:
            logger.error(f"获取远程文件列表时发生错误: {e}")
            return None
    
    def _get_local_files(self):
        """获取本地文件列表及大小
        
        Returns:
            dict: 文件名到文件大小的映射
        """
        files = {}
        try:
            for file_name in os.listdir(self.local_path):
                file_path = os.path.join(self.local_path, file_name)
                if os.path.isfile(file_path):
                    size = os.path.getsize(file_path)
                    files[file_name] = size
            
            logger.info(f"本地文件数量: {len(files)}")
            return files
        except Exception as e:
            logger.error(f"获取本地文件列表时发生错误: {e}")
            return {}
    
    def _upload_file(self, file_name):
        """上传文件到远程服务器
        
        Args:
            file_name: 文件名
            
        Returns:
            bool: 上传是否成功
        """
        local_file_path = os.path.join(self.local_path, file_name)
        remote_file_path = os.path.join(self.remote_path, file_name)
        
        try:
            # 使用SFTP上传文件
            sftp = self.ssh.client.open_sftp()
            logger.info(f"正在上传文件: {file_name}")
            sftp.put(local_file_path, remote_file_path)
            sftp.close()
            logger.info(f"文件上传成功: {file_name}")
            return True
        except Exception as e:
            logger.error(f"上传文件 {file_name} 失败: {e}")
            return False
    
    def _delete_remote_file(self, file_name):
        """删除远程文件
        
        Args:
            file_name: 文件名
            
        Returns:
            bool: 删除是否成功
        """
        remote_file_path = os.path.join(self.remote_path, file_name)
        
        try:
            cmd = f"rm -f \"{remote_file_path}\""
            success, _, error = self.ssh.execute_command(cmd)
            if not success:
                logger.error(f"删除远程文件 {file_name} 失败: {error}")
                return False
            
            logger.info(f"远程文件已删除: {file_name}")
            return True
        except Exception as e:
            logger.error(f"删除远程文件 {file_name} 时发生错误: {e}")
            return False
