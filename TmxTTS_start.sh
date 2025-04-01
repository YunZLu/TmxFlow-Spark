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

    # 颜色定义(登录ubuntu重新配置)
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
             [ ! -x "$(command -v sshpass)" ] && missing+=("sshpass")
             [ ! -x "$(command -v rsync)" ] && missing+=("rsync")
	         [ ! -x "$(command -v python3)" ] && missing+=("python=3")
             [ ! -x "$(command -v yq)" ] && missing+=("yq")
             [ ! -x "$(command -v lolcat)" ] && missing+=("lolcat")
             dpkg -l python3-venv | grep ^ii > /dev/null || missing+=("python3-venv")
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
            if [ ! -f "venv/bin/activate" ]; then
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

# 启动界面
show_menu() {

    # 颜色定义(登录ubuntu重新配置)
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
        echo -e "${GREEN}➤ 1. 启动应用程序            ${YELLOW}➤ 2. 快速远程登录${NC}"
        echo -e "${CYAN}➤ 3. 修改服务器地址/端口     ${BLUE}➤ 4. 修改账户信息${NC}"
        echo -e "${PURPLE}➤ 5. 更新应用程序            ${RED}➤ 0. 退出系统${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}请选择操作 [0-4]:${NC}"
        read option
        
        case $option in
            1)
                CONFIG_FILE="config.yaml"
                # 从YAML读取配置 🔄
                echo -n "🔍 解析配置文件..."
                HOST=$(yq -r '.ssh.host' $CONFIG_FILE 2>/dev/null)
                PORT=$(yq -r '.ssh.port' $CONFIG_FILE 2>/dev/null)
                USER=$(yq -r '.ssh.username' $CONFIG_FILE 2>/dev/null)
                PASSWORD=$(yq -r '.ssh.password' $CONFIG_FILE 2>/dev/null)
                SERVER="$USER@$HOST"
                
                # 调试信息 🔄
                echo -e "\n${YELLOW}=== 🛠️ 调试信息 ===${NC}"
                echo "🏷️ HOST: $HOST"
                echo "🔌 PORT: $PORT"
                echo "👤 USER: $USER"
                echo "🖥️ SERVER: $SERVER"
                
                # 状态检查函数 🔄
                check_status() {
                  if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✅ 成功${NC}"
                  else
                    echo -e "${RED}❌ 失败${NC}"
                    exit 1
                  fi
                }
                
                # 2. 远程启动服务 🔄
                echo -e "\n${YELLOW}=== 🚀 远程服务启动 ===${NC}"
                ssh-keygen -R "[$HOST]:$PORT"
                
                # 文件同步模块 🔄
                echo -e "\n${YELLOW}=== 📂 开始文件同步 ===${NC}"
                
                sync_roles() {
                  REMOTE_PATH="/Fast-Spark-TTS/data/roles/"
                  LOCAL_PATH="./data/roles/"
                
                  mkdir -p ${LOCAL_PATH}
                
                  echo -n "🔄 同步角色文件..."
                  if [ -z "$(ls -A ${LOCAL_PATH})" ]; then
                    sshpass -p "$PASSWORD" rsync -avz --progress \
                      -e "ssh -p $PORT -o StrictHostKeyChecking=no" \
                      ${USER}@${HOST}:${REMOTE_PATH} ${LOCAL_PATH}
                  else
                    sshpass -p "$PASSWORD" rsync -avz --progress --delete \
                      -e "ssh -p $PORT -o StrictHostKeyChecking=no" \
                      ${LOCAL_PATH} ${USER}@${HOST}:${REMOTE_PATH}
                  fi
                  check_status
                }
                sync_roles
                
                sshpass -p "$PASSWORD" ssh -p $PORT -T -o StrictHostKeyChecking=no $USER@$HOST <<'ENDSSH'
                # 清理旧进程 🔄
                echo "🛑 正在停止旧服务..."
                pkill -f "python" && echo "✅ 已停止所有Python进程" || echo "ℹ️ 没有Python进程在运行"
                sleep 1
                
                # 清理旧日志
                mv ~/server.log ~/server.log.bak 2>/dev/null
                
                # 启动新服务 🔄
                cd /Fast-Spark-TTS/
                echo "🚀 启动 server.py..."
                nohup /root/miniconda3/bin/python server.py --model_path Spark-TTS-0.5B --backend vllm --llm_device cuda --tokenizer_device cuda --detokenizer_device cuda --wav2vec_attn_implementation sdpa --llm_attn_implementation sdpa --torch_dtype "bfloat16" --max_length 32768 --llm_gpu_memory_utilization 0.6 --host 0.0.0.0 --port 8000 > ~/server.log 2>&1 &
                
                echo "🌐 启动 frontend.py..."
                nohup /root/miniconda3/bin/python frontend.py --backend_url http://127.0.0.1:8000 --host 0.0.0.0 --port 8001 > ~/frontend.log 2>&1 &
                
                # 服务状态检查 🔄
                echo "⏳ 等待后端服务初始化（请耐心等待三分钟）..."
                timeout=180
                start_time=$(date +%s)
                while true; do
                  if grep -q "Warmup complete" ~/server.log; then
                    echo -e "${GREEN}🎉 后端服务已准备就绪${NC}"
                    break
                  fi
                  current_time=$(date +%s)
                  if (( current_time - start_time >= timeout )); then
                    echo -e "${RED}⏰ 后端服务启动超时，请检查 ~/server.log${NC}"
                    exit 1
                  fi
                  sleep 5
                done
                
                if pgrep -f "frontend.py" >/dev/null; then
                  echo -e "${GREEN}🌍 前端服务已准备就绪${NC}"
                else
                  echo -e "${RED}❌ 前端服务启动失败，请检查 ~/server.log${NC}"
                  exit 1
                fi
ENDSSH
                check_status
                
                # 3. 建立本地隧道 🔄
                echo -e "\n${YELLOW}=== 🔗 本地隧道建立 ===${NC}"
                
                establish_tunnel() {
                  echo -n "🛰️ 建立隧道 $1..."
                  sshpass -p "$PASSWORD" ssh -L $1:localhost:$1 -p $PORT -fNq $SERVER
                  if ps aux | grep -q "[s]sh -L $1"; then
                    echo -e "${GREEN}✅ 成功${NC}"
                  else
                    echo -e "${RED}❌ 失败${NC}"
                  fi
                }
                
                establish_tunnel 8000
                establish_tunnel 8001
                
                # 4. 最终验证 🔄
                echo -e "\n${YELLOW}=== 🧪 最终验证 ===${NC}"
                
                check_port() {
                  echo -n "🔍 测试端口 $1..."
                  if curl -Ism 2 http://localhost:$1 >/dev/null; then
                    echo -e "${GREEN}✅ 活跃${NC}"
                  else
                    echo -e "${YELLOW}⚠️ 未响应${NC}"
                  fi
                }
                
                echo -e "\n🔧 后端服务状态："
                check_port 8000
                echo -e "\n🖥️ 前端服务状态："
                check_port 8001
                
                echo -e "\n🚨 访问测试："
                echo -e "${GREEN}🔧 后端服务：${NC}curl -I http://localhost:8000"
                echo -e "${GREEN}🌐 前端界面：${NC}打开浏览器访问 http://localhost:8001"
                echo -e "\n${CYAN}🚀 正在启动应用...${NC}"
                cd /root/TmxFlow-Spark
                source venv/bin/activate
                python3 main.py
                deactivate
                echo -e "${YELLOW}按回车键返回主菜单...${NC}"
                read
                ;;
            2)
                echo -e "\n${CYAN}请选择要登录的服务器域名：${NC}"
                echo -e "${YELLOW}1. hn-a.suanjiayun.com${NC}"
                echo -e "${YELLOW}2. hn-b.suanjiayun.com${NC}"
                echo -e "${YELLOW}3. xn-a.suanjiayun.com${NC}"
                echo -e "${YELLOW}4. xn-b.suanjiayun.com${NC}"
                echo -e "${YELLOW}请选择域名 [1-4]:${NC}"
                read domain_choice
                
                case $domain_choice in
                    1) domain="hn-a.suanjiayun.com" ;;
                    2) domain="hn-b.suanjiayun.com" ;;
                    3) domain="xn-a.suanjiayun.com" ;;
                    4) domain="xn-b.suanjiayun.com" ;;
                    *)
                        echo -e "${RED}错误：无效的域名选择！${NC}"
                        echo -e "${YELLOW}按回车键返回主菜单...${NC}"
                        read
                        continue
                        ;;
                esac
                
                echo -e "${YELLOW}请输入用户名：${NC}"
                read username
                
                echo -e "\n${CYAN}🚀 正在登录服务器 $domain ...${NC}"
                ssh -p 2020 "$username@$domain"
                
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
                
                yq -y --arg username "$username" --arg password "$password" '.ssh.username = $username | .ssh.password = $password' "$config_file" -i
                
                if [ $? -eq 0 ]; then
                    echo -e "\n${GREEN}✅ 账户信息已更新！当前配置${NC}"
                    yq '.ssh' "$config_file"
                else
                    echo -e "${RED}❌ 更新失败，请检查配置文件！${NC}"
                fi
                echo -e "${YELLOW}按回车键返回主菜单...${NC}"
                read
                ;;
            5)
                echo -e "\n${CYAN}🔄 正在更新应用程序...${NC}"
                cd /root/TmxFlow-Spark
                git pull && echo -e "\n${GREEN}✅ 应用程序已更新${NC}\n"
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
            echo -e "${BLUE}🛠️ 正在安装openssh...${NC}"
            pkg update -y && pkg install openssh -y && echo -e "\n${GREEN}✅ SSH安装成功，可以开始连接远程服务器了${NC}"
        fi
	
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
