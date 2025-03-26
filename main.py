import os
import logging
from werkzeug.serving import run_simple
from core.logger import setup_logger
from core.ssh_manager import SSHManager
from core.sync_manager import FileSynchronizer
from api.routes import create_app
from utils.helpers import get_local_ip,load_config

# 欢迎页面
def show_welcome():
    print("\033[38;5;213m")  # 使用柔和的品红色
    print("  ╭"+"─"*64+"╮")
    print("  │ \033[1;38;5;231m🦄 \033[38;5;219mTermux Flow Spark-TTS Server  \033[0;38;5;213mv1.0.0"+ " "*24 +"│")
    print("  ├"+"─"*64+"┤")
    print("  │ \033[38;5;219m✦ 数据流向示意图：" + "━"*40 + "━━━┓ \033[38;5;213m│")
    print("  │ \033[38;5;225m   🎼 Spark-TTS → 🦊 Proxy Server → 📦 Cache →  🌸 SillyTevan\033[38;5;213m  │")
    print("  │ \033[38;5;219m  ┗" + "━"*55 + "━━   \033[38;5;213m│")
    print("  ├"+"─"*64 +"┤")
    print("  │ \033[38;5;226m📂 存储规则：" + " "*47 + "\033[38;5;213m   │")
    print("  │ \033[38;5;226m├─\033[38;5;228m 1. 音频保存至本地后，会自动删除 \033[3m服务器 \033[0;38;5;228m音频 "+ " "*16 +"\033[38;5;213m│")
    print("  │ \033[38;5;226m├─\033[38;5;228m 2. prompt_audio文件夹数据将自动上传至 \033[3m服务器\033[0;38;5;228m 同名文件夹"+ " "*5 +"\033[38;5;213m│")
    print("  │ \033[38;5;226m└─\033[38;5;228m 3. text_file文件夹数据将上传至\033[3m 服务器\033[0;38;5;228m 同名文件夹"+ " "*12 +"\033[38;5;213m│") 
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

def main():
    """主函数"""
    try:
        # 加载配置
        config = load_config()
        
        # 创建目录
        os.makedirs(config['local']['cache_dir'], exist_ok=True)
        os.makedirs(config['local']['local_prompt_audio_path'], exist_ok=True)
        os.makedirs(config['local']['local_prompt_text_path'], exist_ok=True)
        os.makedirs(config['local']['local_text_file_path'], exist_ok=True)
        
        # 创建SSH连接
        ssh_client = SSHManager(config)
        if not ssh_client.connect():
            logger.critical("无法连接到远程服务器，服务无法启动")
            exit(1)
        
        # 同步提示音频文件
        audio_sync = FileSynchronizer(
            ssh_client,
            config['local']['local_prompt_audio_path'],
            os.path.join(config['tts']['workdir'], config['tts']['remote_prompt_audio_path'])
        )
        if not audio_sync.sync_files():
            logger.warning("提示音频文件同步失败，但服务仍然启动……")
        
        # 同步文本文件
        text_sync = FileSynchronizer(
            ssh_client,
            config['local']['local_text_file_path'],
            os.path.join(config['tts']['workdir'], config['tts']['remote_text_file_path'])
        )
        if not text_sync.sync_files():
            logger.warning("语音生成文本文件同步失败，但服务仍然启动……")
        
        # 创建应用
        app = create_app(config)
        
        # 启动服务
        port = config['local']['port']
        local_ip = get_local_ip()
        
        logger.info(f"Spark-TTS反代理服务启动成功！")
        logger.info(f"本地访问: http://127.0.0.1:{port}")
        logger.info(f"示例请求: http://127.0.0.1:{port}/tts?text=欢迎使用TmxFlow-Spark&prompt_audio=芙宁娜")
        
        # 使用 run_simple 启动应用
        run_simple('0.0.0.0', port, app, use_reloader=False, threaded=True)
        
    except Exception as e:
        logger.critical(f"服务启动失败: {e}")
        exit(1)

if __name__ == '__main__':
    show_welcome()
    main()
