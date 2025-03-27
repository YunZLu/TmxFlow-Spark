#!/bin/bash
# 定义Ubuntu的安装目录路径
UBUNTU_DIR="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu"
termux_home="/data/data/com.termux/files/home"
current_dir=$(pwd)
config_file="/root/TmxFlow-Spark/config.yaml"

# 颜色定义
RED='\033[38;5;203m'      # 浅珊瑚红
GREEN='\033[38;5;114m'    # 灰调青绿
YELLOW='\033[38;5;228m'   # 香草奶油黄
BLUE='\033[38;5;111m'     # 雾霾蓝
CYAN='\033[38;5;122m'     # 浅湖蓝
PURPLE='\033[38;5;183m'   # 薰衣草紫
NC='\033[0m'

# 部署流程
deploy() {

# 颜色定义
RED='\033[38;5;203m'      # 浅珊瑚红
GREEN='\033[38;5;114m'    # 灰调青绿
YELLOW='\033[38;5;228m'   # 香草奶油黄
BLUE='\033[38;5;111m'     # 雾霾蓝
CYAN='\033[38;5;122m'     # 浅湖蓝
PURPLE='\033[38;5;183m'   # 薰衣草紫
NC='\033[0m'

        # 添加termux上的Ubuntu/root软链接
        if [ ! -d "/data/data/com.termux/files/home/root" ]; then
            ln -s /data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/ubuntu/root /data/data/com.termux/files/home
        fi
        
        # Ubuntu环境处理
        echo -e "\n${BLUE}🌐 正在检测系统环境...${NC}"
        
        # 基础依赖检查
        check_deps() {
             local missing=()
             [ ! -x "$(command -v git)" ] && missing+=("git")
	         [ ! -x "$(command -v python3)" ] ||&& missing+=("python=3")
             [ ! -x "$(command -v yq)" ] && missing+=("yq")
             [ ! -x "$(command -v lolcat)" ] && missing+=("lolcat")
             dpkg -l python3-venv | grep ^ii || missing+=("python3-venv")
             # 安装依赖
             if [ ${#missing[@]} -gt 0 ]; then
                   echo -e "${YELLOW}⚠️ 缺少依赖: ${missing[*]}${NC}"
                   echo -e "${BLUE}🛠️ 正在配置镜像源并安装依赖...${NC}"
                   bash -s < <(curl -sSL https://linuxmirrors.cn/main.sh)
                   apt update -y && apt install -y ${missing[@]}
             fi
           }
        
        # 克隆仓库
        check_repo() {
            if [ ! -d "/root/TmxFlow-Spark" ]; then
                echo -e "${YELLOW}⏬ 正在克隆仓库...${NC}"
                cd /root
                git clone https://github.com/YunZLu/TmxFlow-Spark.git || {
                    echo -e "${RED}❌ 仓库克隆失败!${NC}"
                    exit 1
                }
                echo -e "${GREEN}✅ 仓库克隆成功!${NC}"
            fi
        }

        # 配置Python环境
        setup_python() {
            cd TmxFlow-Spark || exit 1
            if [ ! -d "venv/bin/activate" ]; then
                echo -e "${BLUE}🐍 正在创建虚拟环境...${NC}"
                python3 -m venv venv
                echo -e "${BLUE}📦 正在安装依赖...${NC}"
                source venv/bin/activate
                pip config set global.index-url https://mirrors.aliyun.com/pypi/simple/
                pip install -r requirements.txt

                deactivate
                echo -e "${GREEN}✅ 环境配置完成!${NC}"
            fi
        }

        # 执行检查流程
        check_deps
        check_repo
        setup_python
}

show_menu() {

# 颜色定义
RED='\033[38;5;203m'      # 浅珊瑚红
GREEN='\033[38;5;114m'    # 灰调青绿
YELLOW='\033[38;5;228m'   # 香草奶油黄
BLUE='\033[38;5;111m'     # 雾霾蓝
CYAN='\033[38;5;122m'     # 浅湖蓝
PURPLE='\033[38;5;183m'   # 薰衣草紫
NC='\033[0m'

config_file="/root/TmxFlow-Spark/config.yaml"

    while true; do
        clear
        cat /root/TmxFlow-Spark/TMX_logo.txt | lolcat 
        echo -e "${BLUE}\n════════════════════════════════════════════════════════════════════════════${NC}"

echo -e "${GREEN}➤ 1. 启动应用程序            ${YELLOW}➤ 2. 查看当前配置${NC}"
echo -e "${CYAN}➤ 3. 修改服务器地址/端口     ${PURPLE}➤ 4. 修改账户信息${NC}"
echo -e "${RED}➤ 0. 退出系统${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}请选择操作 [0-4]:${NC}"
        read option
        
        case $option in
            1)
                echo -e "\n${CYAN}🚀 正在启动应用...${NC}"
                cd /root/TmxFlow-Spark
                source venv/bin/activate
                python3 main.py
                deactivate
                echo -e "${YELLOW}按回车键返回主菜单...${NC}"
                read
                ;;
            2)
                echo -e "\n${GREEN}🔍 当前服务器配置信息：${NC}"
                yq '.ssh' "$config_file"
                echo -e "${YELLOW}按回车键返回主菜单...${NC}"
                read
                ;;
            3)
                echo -e "\n${YELLOW}🛠️ 请输入服务器地址（格式 host:port 或 tcp://host:port）"
                echo -e "示例：tcp://18.tcp.cpolar.top:12345${NC}"
                read -p "» " ssh_input

                ssh_input=${ssh_input#tcp://}
                
                if [[ ! "$ssh_input" =~ ^[^:]+:[0-9]+$ ]]; then
                    echo -e "${RED}❌ 输入格式无效！请使用 host:port 格式${NC}"
                    sleep 2
                    continue
                fi
                
                host=${ssh_input%:*}
                port=${ssh_input##*:}
                
                yq -y --arg host "$host" --arg port "$port" '.ssh.host = $host | .ssh.port = $port' "$config_file" -i
                
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✅ 配置更新成功！当前配置：${NC}"
                    yq '.ssh' "$config_file"
                else
                    echo -e "${RED}❌ 配置更新失败，请检查文件权限！${NC}"
                fi
                echo -e "${YELLOW}按回车键返回主菜单...${NC}"
                read
                ;;
            4)
                echo -e "\n${YELLOW}🔑 账户信息修改\n"
                echo -e "请输入新的用户名:${NC}"
                read  username
                echo -e "\n${YELLOW}请输入新的密码:${NC}"
                read password
                
                yq -y --arg username "$username" --arg password "$password" '.username = $username | .ssh.password = $password' "$config_file" -i
                
                if [ $? -eq 0 ]; then
                    echo -e "\n${GREEN}✅ 账户信息已更新！当前配置${NC}"
                    yq '.ssh' "$config_file"
                else
                    echo -e "${RED}❌ 更新失败，请检查配置文件！${NC}"
                fi
                echo -e "${YELLOW}按回车键返回主菜单...${NC}"
                read
                ;;
            0)
                echo -e "\n${YELLOW}👋 正在退出系统...${NC}\n"
                exit 0
                ;;
            *)
                echo -e "${RED}⚠️ 无效选项，请重新输入！${NC}"
                sleep 1
                ;;
        esac
    done
}

# 环境检测
if [ "$current_dir" = "$termux_home" ]; then
    echo -e "${CYAN}📱 检测到Termux环境，正在准备Ubuntu环境...${NC}"
    
    if [ ! -d "$UBUNTU_DIR" ]; then
        echo -e "${YELLOW}⚠️ 未检测到Ubuntu子系统，正在安装...${NC}"
        
        if ! command -v proot-distro; then
            echo -e "${BLUE}🛠️ 正在安装proot-distro...${NC}"
            pkg update -y && pkg install proot-distro -y
        fi
        
        proot-distro install ubuntu
    fi
    proot-distro login ubuntu -- bash -c "
        $(declare -f deploy show_menu)
        deploy
        show_menu
    "
else
    echo -e "${CYAN}🖥️ 检测到Ubuntu环境，开始部署...${NC}"
    deploy
    show_menu
fi
