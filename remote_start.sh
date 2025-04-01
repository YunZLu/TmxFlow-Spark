#!/bin/bash

# 仅限交互式终端运行
if [[ ! -t 0 ]]; then
    echo -e "\033[31m🚨 错误：此脚本必须在交互式终端中运行。\033[0m" >&2
    exit 1
fi

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
MAGENTA='\033[35m'
CYAN='\033[36m'
BOLD='\033[1m'
RESET='\033[0m'

# 部署流程函数
deploy_process() {
    echo -e "\n${BOLD}${CYAN}🌟 开始部署 Fast-Spark-TTS 系统${RESET}"
    echo -e "${MAGENTA}========================================${RESET}"

    # 检查必要工具
    echo -e "\n${BLUE}🔍 检查系统必要工具...${RESET}"
    for pkg in python3 git unzip; do
        if ! command -v $pkg &> /dev/null; then
            echo -e "${YELLOW}⚠️  未找到 $pkg，正在安装...${RESET}"
            apt update -qq && apt install -y $pkg
            echo -e "${GREEN}✅ $pkg 安装完成！${RESET}"
        else
            echo -e "${CYAN}✔️  $pkg 已安装${RESET}"
        fi
    done
    
    # 安装ssh
    if [ ! -f "/etc/init.d/ssh" ]; then
        apt update && apt install -y ssh
    fi

    # 克隆仓库
    echo -e "\n${BLUE}📂 克隆项目仓库...${RESET}"
    if [ ! -d "/Fast-Spark-TTS" ]; then
        git clone https://gh-proxy.com/https://github.com/HuiResearch/Fast-Spark-TTS.git /Fast-Spark-TTS
        echo -e "${GREEN}✅ 仓库克隆完成！${RESET}"
        # 替换torch为vllm，并追加flask
        sed -i 's/^torch==2\.5\.1$/vllm/' requirements.txt && echo -e "\nflask" >> requirements.txt
    else
        echo -e "${CYAN}✔️  项目已存在，跳过克隆${RESET}"
    fi

    # 安装依赖
    echo -e "\n${BLUE}⚙️  安装Python依赖...${RESET}"
    cd /Fast-Spark-TTS || exit
    
    REQUIREMENTS_FILE="${1:-requirements.txt}"
    
    if [ ! -f "$REQUIREMENTS_FILE" ]; then
        echo -e "${RED}🚨 错误：依赖文件 $REQUIREMENTS_FILE 不存在！${RESET}"
        exit 1
    fi
    
    echo -e "${CYAN}🔍 检查依赖文件：$REQUIREMENTS_FILE${RESET}"
    grep -vE '^\s*$|^\s*#' "$REQUIREMENTS_FILE" | while read -r line; do
        pkg_name=$(echo "$line" | sed -E 's/[[:space:]]*([^!=<>=]+).*/\1/')
        if pip show "$pkg_name" &>/dev/null; then
            echo -e "${CYAN}✔️  已安装：$pkg_name${RESET}"
        else
            echo -e "${YELLOW}➡️  正在安装：$line${RESET}"
            pip install "$line"
        fi
    done
    
    # 下载模型
    echo -e "\n${BLUE}🤖 下载语音模型...${RESET}"
    mkdir -p Spark-TTS-0.5B
    if [ ! -d "Spark-TTS-0.5B" ] || [ -z "$(ls -A Spark-TTS-0.5B)" ]; then
        pip install -U -q huggingface_hub
        export HF_ENDPOINT=https://hf-mirror.com
        echo -e "${YELLOW}⏳ 正在从镜像站下载模型，请耐心等待...${RESET}"
        huggingface-cli download --force-download SparkAudio/Spark-TTS-0.5B --local-dir Spark-TTS-0.5B
        echo -e "${GREEN}✅ 模型下载完成！${RESET}"
    else
        echo -e "${CYAN}✔️  模型已存在，跳过下载${RESET}"
    fi

    # 安装cpolar
    echo -e "\n${BLUE}🌐 配置内网穿透工具...${RESET}"
    cd / || exit
    if [ ! -f "cpolar" ]; then
        echo -e "${YELLOW}⬇️  下载cpolar客户端...${RESET}"
        wget --show-progress -q -O "cpolar.zip" "https://www.cpolar.com/static/downloads/releases/3.3.18/cpolar-stable-linux-amd64.zip"
        unzip -o -q cpolar.zip
        chmod +x cpolar
        token=""
        while [ -z "$token" ]; do
            echo -e "${CYAN}🔑 请输入您的cpolar token（可在官网控制台获取）：${RESET}"
            read -p "> " token
        done
        ./cpolar authtoken "$token"
        echo -e "${GREEN}✅ cpolar配置完成！${RESET}"
    else
        echo -e "${CYAN}✔️  cpolar已安装，跳过配置${RESET}"
    fi

    # 配置SSH
    echo -e "\n${BLUE}🔐 配置SSH服务...${RESET}"
    need_config=0
    grep -qxF "PermitRootLogin yes" /etc/ssh/sshd_config || { echo "PermitRootLogin yes" >> /etc/ssh/sshd_config; need_config=1; }
    grep -qxF "Port 2020" /etc/ssh/sshd_config || { echo "Port 2020" >> /etc/ssh/sshd_config; need_config=1; }
    
    if [ $need_config -eq 1 ]; then
        echo -e "${YELLOW}🛠️  需要配置SSH，请设置root密码：${RESET}"
        passwd root
        /etc/init.d/ssh restart
        echo -e "${GREEN}✅ SSH配置更新完成！${RESET}"
    else
        echo -e "${CYAN}✔️  SSH配置已生效，跳过修改${RESET}"
    fi
    
    # 设置自启动
    echo -e "\n${BLUE}🔄 配置自启动服务...${RESET}"
    if ! grep -q "remote_start.sh" /root/.bashrc; then
        echo -e "\n# Fast-Spark-TTS自动启动\n/usr/local/bin/remote_start.sh" >> /root/.bashrc
        echo -e "${GREEN}✅ 自启动配置完成！${RESET}"
    else
        echo -e "${CYAN}✔️  自启动配置已存在${RESET}"
    fi
}

# 启动流程函数
start_process() {
    echo -e "\n${BOLD}${GREEN}🚀 系统部署完成，进入运行管理界面${RESET}"
    echo -e "${MAGENTA}========================================${RESET}"

    /etc/init.d/ssh restart
    
    while true; do
        echo -e "\n${BOLD}${CYAN}请选择操作：${RESET}"
        echo -e "1. 🚀 启动cpolar内网穿透"
        echo -e "2. 🔑 修改cpolar token"
        echo -e "3. 🔒 修改root密码"
        echo -e "0. 🚪 退出系统"
        echo -ne "${BOLD}👉 请输入数字选择 [0-3]: ${RESET}"
        read -r choice

        case $choice in
            1) 
                echo -e "\n${YELLOW}⏳ 正在启动cpolar服务...${RESET}"
                pkill -f cpolar
                ./cpolar tcp 2020 > /dev/null &
                echo -e "${GREEN}✅ cpolar已启动！访问地址：${CYAN}https://dashboard.cpolar.com${RESET}"
                ;;
            2) 
                echo -ne "\n${CYAN}请输入新的cpolar token: ${RESET}"
                read -r new_token
                ./cpolar authtoken "$new_token"
                echo -e "${GREEN}✅ Token更新成功！${RESET}"
                ;;
            3) 
                echo -e "\n${YELLOW}🔐 正在修改root密码...${RESET}"
                passwd root
                ;;
            0) 
                echo -e "\n${GREEN}🎉 感谢使用，再见！${RESET}"
                exit 0
                ;;
            *) 
                echo -e "${RED}🚨 无效输入，请重新选择${RESET}"
                ;;
        esac
    done
}

# 主执行流程
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}🚨 请使用root权限运行脚本！${RESET}"
    exit 1
fi

deploy_process
start_process
