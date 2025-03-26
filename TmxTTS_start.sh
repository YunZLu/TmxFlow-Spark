#!/bin/bash

termux_home="/data/data/com.termux/files/home"
current_dir=$(pwd)
config_file="TmxFlow-Spark/config.yaml"

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
NC='\033[0m'

# 部署流程
auto_deploy() {
    # Termux环境处理
    if [ "$current_dir" = "$termux_home" ]; then
        echo -e "${CYAN}[+] 检测到Termux环境${NC}"
        
        # 检查Ubuntu发行版
        if ! proot-distro list | grep -q ubuntu; then
            echo -e "${YELLOW}[!] 正在安装Ubuntu...${NC}"
            pkg update -y && pkg install proot-distro -y
            proot-distro install ubuntu
        fi

        # 进入Ubuntu继续执行
        echo -e "${CYAN}[→] 进入Ubuntu环境...${NC}"
        proot-distro login ubuntu -- bash -c "cd ~ && curl -sL https://raw.githubusercontent.com/YunZLu/TmxFlow-Spark/refs/heads/main/TmxTTS_start.sh | bash"
        exit 0
    else
        # Ubuntu环境处理
        echo -e "${CYAN}[+] 正在检测系统环境...${NC}"
        
        # 基础依赖检查
        check_deps() {
            local missing=()
            [ ! -x "$(command -v git)" ] && missing+=("git")
            [ ! -x "$(command -v python3)" ] && missing+=("python3")
            
            if [ ${#missing[@]} -gt 0 ]; then
                bash -s < <(curl -sSL https://linuxmirrors.cn/main.sh)
                echo -e "${YELLOW}[!] 缺少依赖: ${missing[*]}${NC}"
                apt update -y && apt install -y ${missing[@]}
            fi
        }
        
        # 克隆仓库
        check_repo() {
            if [ ! -d "TmxFlow-Spark" ]; then
                echo -e "${YELLOW}[!] 正在克隆仓库...${NC}"
                git clone https://github.com/YunZLu/TmxFlow-Spark.git || {
                    echo -e "${RED}[!] 仓库克隆失败!${NC}"
                    exit 1
                }
            fi
        }

        # 准备Python环境
        setup_python() {
            cd TmxFlow-Spark || exit 1
            if [ ! -d "venv" ]; then
                echo -e "${YELLOW}[!] 正在创建虚拟环境...${NC}"
                python3 -m venv venv
                echo -e "${YELLOW}[!] 正在安装依赖...${NC}"
                source venv/bin/activate
                pip config set global.index-url https://mirrors.aliyun.com/pypi/simple/
                pip install -r requirements.txt
                deactivate
            fi
        }

        # 执行检查流程
        check_deps
        check_repo
        setup_python
    fi
}

# 启动界面
show_menu() {
    while true; do
        clear
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}|      ${GREEN}TMXFLOW-SPARK 控制中心${BLUE}      |${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo -e "${GREEN}1. 启动应用程序${NC}"
        echo -e "${YELLOW}2. 修改服务器地址/端口${NC}"
        echo -e "${YELLOW}3. 修改用户名和密码${NC}"
        echo -e "${RED}0. 退出${NC}"
        echo -e "${BLUE}========================================${NC}"
        read -p "请输入选项: " option
        
        case $option in
            1)
                echo -e "${CYAN}[→] 正在启动应用...${NC}"
                source venv/bin/activate
                python main.py
                deactivate
                read -p "按回车键返回菜单..."
                ;;
            2)
                read -p "请输入新的服务器地址: " ssh_input
                ssh_input=${ssh_input#tcp://}
                host=${ssh_input%:*}
                port=${ssh_input##*:}
                
                sed -i "s/  host: .*/  host: $host/" $config_file
                sed -i "s/  port: .*/  port: $port/" $config_file
                echo -e "${GREEN}[√] 服务器地址已更新！${NC}"
                sleep 1
                ;;
            3)
                read -p "请输入新的用户名: " username
                read -sp "请输入新的密码: " password
                echo
                
                sed -i "s/  username: .*/  username: $username/" $config_file
                sed -i "s/  password: .*/  password: $password/" $config_file
                echo -e "${GREEN}[√] 认证信息已更新！${NC}"
                sleep 1
                ;;
            0)
                echo -e "${RED}[!] 退出系统...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}[!] 无效选项，请重新输入！${NC}"
                sleep 1
                ;;
        esac
    done
}

# 全自动流程
{
    auto_deploy    # 执行自动部署
    cd TmxFlow-Spark 2>/dev/null || exit 1
    show_menu      # 进入控制菜单
}