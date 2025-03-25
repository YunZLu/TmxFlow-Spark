#!/bin/bash

# 仅限交互式终端运行
if [[ ! -t 0 ]]; then
    echo "错误：此脚本必须在交互式终端中运行。" >&2
    exit 1
fi

# 部署流程函数
deploy_process() {
    # 检查必要工具
    for pkg in ssh git unzip; do
        if ! command -v $pkg &> /dev/null; then
            apt update && apt install -y $pkg
        fi
    done

    # 克隆仓库
    if [ ! -d "/Spark-TTS" ]; then
        git clone https://github.com/SparkAudio/Spark-TTS.git /Spark-TTS
    fi

    # 创建conda环境
    cd /Spark-TTS || exit
    if ! conda env list | grep -q "sparktts"; then
        conda create -n sparktts -y python=3.12
        # 安装依赖
        source /root/miniconda3/etc/profile.d/conda.sh
        conda activate sparktts
        pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host=mirrors.aliyun.com
    fi


    # 下载模型
    mkdir -p pretrained_models/Spark-TTS-0.5B
    if [ ! -d "pretrained_models/Spark-TTS-0.5B" ] || [ -z "$(ls -A pretrained_models/Spark-TTS-0.5B)" ]; then
        pip install -U huggingface_hub
        export HF_ENDPOINT=https://hf-mirror.com
        huggingface-cli download --force-download SparkAudio/Spark-TTS-0.5B --local-dir pretrained_models/Spark-TTS-0.5B
    fi

    # 下载必要文件
    declare -A files=(
        ["tts_cli.py"]="cli/tts_cli.py"
        ["SparkTTS.py"]="cli/SparkTTS.py"
        ["BiCodec.py"]="sparktts/models/BiCodec.py"
    )
    for file in "${!files[@]}"; do
        if [ ! -f "${files[$file]}" ]; then
            wget -q "https://raw.githubusercontent.com/YunZLu/TmxFlow-Spark/main/RemoteFile/$file" -O "${files[$file]}"
        fi
    done

    # 安装cpolar（仅首次安装时设置token）
    cd / || exit
    if [ ! -f "cpolar" ]; then
        wget --show-progress -q -O "cpolar.zip" "https://www.cpolar.com/static/downloads/releases/3.3.18/cpolar-stable-linux-amd64.zip"
        unzip -o cpolar.zip
        chmod +x cpolar
        read -p "请输入cpolar token: " token
        ./cpolar authtoken "$token"
    fi

    # 配置SSH（仅在首次配置时设置密码）
    need_config=0
    grep -qxF "PermitRootLogin yes" /etc/ssh/sshd_config || { echo "PermitRootLogin yes" >> /etc/ssh/sshd_config; need_config=1; }
    grep -qxF "Port 2020" /etc/ssh/sshd_config || { echo "Port 2020" >> /etc/ssh/sshd_config; need_config=1; }
    
    if [ $need_config -eq 1 ]; then
        echo "请设置root密码："
        passwd root
        /etc/init.d/ssh restart
    fi
    
    # 设置自启动
    if ! grep -q "remote_start.sh" /root/.bashrc; then
        echo -e "\n# SparkTTS自动启动\n/usr/local/bin/remote_start.sh" >> /root/.bashrc
    fi
}

# 启动流程函数（保持不变）
start_process() {

    /etc/init.d/ssh restart
    
    while true; do
        echo ""
        echo "请选择操作："
        echo "1. 启动cpolar"
        echo "2. 修改cpolar token"
        echo "3. 修改root密码"
        echo "0. 退出"
        read -p "请输入数字选择: " choice

        case $choice in
            1) nohup ./cpolar tcp 2020 & ;;
            2) 
                read -p "请输入新token: " new_token
                ./cpolar authtoken "$new_token"
                ;;
            3) passwd root ;;
            0) exit 0 ;;
            *) echo "无效输入，请重新选择" ;;
        esac
    done
}

# 主执行流程（保持不变）
if [ "$(id -u)" != "0" ]; then
    echo "请使用root权限运行脚本！"
    exit 1
fi

deploy_process
start_process
