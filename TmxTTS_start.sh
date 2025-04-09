#!/bin/bash
# 定义Ubuntu的安装目录路径
termux_home="/data/data/com.termux/files/home"
current_dir=$(pwd)
TTS_dir="$current_dir/TmxFlow-Spark"
config_file="$TTS_dir/config.yaml"

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
        # 环境检查
        echo -e "\n${BLUE}🌐 正在检测系统环境...${NC}"
        
        # 基础依赖检查
        check_deps() {
            local missing=()
            [ ! -x "$(command -v git)" ] && missing+=("git")
            [ ! -x "$(command -v sshpass)" ] && missing+=("sshpass")
            [ ! -x "$(command -v rsync)" ] && missing+=("rsync")
            [ ! -x "$(command -v python3)" ] ||。 ! python3 -c "import ensurepip; import venv" &>/dev/null && missing+=("python3")
            [ ! -x "$(command -v yq)" ] && missing+=("yq")
            [ ! -x "$(command -v ssh)" ] && missing+=("openssh")
            
            # 安装基础依赖
            if [ ${#missing[@]} -gt 0 ]; then
                echo -e "${YELLOW}⚠️ 缺少依赖: ${missing[*]}${NC}"
                apt update -y && apt install -y ${missing[@]}
            fi
        
            # 单独处理 lolcat 安装
            if ! command -v lolcat &>/dev/null; then
                echo -e "${YELLOW}⚠️ 缺少依赖: lolcat${NC}"
                echo -e "${BLUE}🛠️ 正在安装 Ruby 和 lolcat...${NC}"
                apt install -y ruby || {
                    echo -e "${RED}安装 Ruby 失败${NC}"
                    exit 1
                }
                # 确保 gem 环境变量已加载
                export PATH="$HOME/.gem/ruby/$(ls -1t $HOME/.gem/ruby | head -n1)/bin:$PATH"
                gem install lolcat || {
                    echo -e "${RED}安装 lolcat 失败${NC}"
                    exit 1
                }
            fi
        }
        
        # 克隆仓库
        check_repo() {
            if [ ! -d $TTS_dir ]; then
                echo -e "${YELLOW}⏬ 正在克隆仓库...${NC}"
                cd $current_dir
                git clone -b Tencent_CS https://github.com/YunZLu/TmxFlow-Spark.git || {
                    echo -e "${RED}❌ 仓库克隆失败!${NC}"
                    exit 1
                }
                echo -e "${GREEN}✅ 仓库克隆成功!${NC}"
            fi
        }

        # 配置Python环境
        setup_python() {
            cd $TTS_dir || exit 1
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


# 配置解析函数
parse_config() {
    echo -n "🔍 解析配置文件..."
    HOST=$(yq -r '.ssh.host' $config_file 2>/dev/null)
    PORT=$(yq -r '.ssh.port' $config_file 2>/dev/null)
    USER=$(yq -r '.ssh.username' $config_file 2>/dev/null)
    PASSWORD=$(yq -r '.ssh.password' $config_file 2>/dev/null)
    SERVER="$USER@$HOST"
    echo -e "${GREEN}完成${NC}"
}

# 公共函数定义
check_status() {
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ 成功${NC}"
  else
    echo -e "${RED}❌ 失败${NC}"
  fi
}

sync_roles() {
  # 清除已知主机记录
  ssh-keygen -R "[$HOST]:$PORT" >/dev/null 2>&1
  REMOTE_PATH="/Fast-Spark-TTS/data/roles/"
  LOCAL_PATH="$TTS_dir/data/roles/"

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

establish_tunnel() {
  # 先终止该端口所有现存隧道
  pids=$(ps aux | grep "[s]sh.*-L.*:$1" | awk '{print $2}')
  if [ -n "$pids" ]; then
    echo -e "🕙 清理现存连接..."
    echo $pids | xargs kill -9 >/dev/null 2>&1
    sleep 1 # 等待进程完全退出
  fi

  # 清除已知主机记录
  ssh-keygen -R "[$HOST]:$PORT" >/dev/null 2>&1
  echo -n "🛰️ 建立隧道 $1..."
  
  # 建立新连接
  sshpass -p "$PASSWORD" ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    -L $1:localhost:$1 \
    -p $PORT \
    -fNq $SERVER

  # 状态检测
  if ps aux | grep -q "[s]sh.*-L.*:$1"; then
    echo -e "${GREEN}✅ 成功${NC}"
  else
    echo -e "${RED}❌ 失败${NC}"
  fi
}

check_port() {
  echo -n "🔍 测试端口 $1..."
  if curl -Ism 2 http://localhost:$1 >/dev/null; then
    echo -e "${GREEN}✅ 活跃${NC}"
  else
    echo -e "${YELLOW}⚠️ 未响应${NC}"
  fi
}

# 启动界面
show_menu() {

    while true; do
        clear
        cat $TTS_dir/TMX_logo.txt | lolcat 
        echo -e "${BLUE}\n════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}➤ 1. 启动应用程序            ${YELLOW}➤ 2. 同步远程文件${NC}"
        echo -e "${CYAN}➤ 3. 修改服务器地址/端口     ${BLUE}➤ 4. 修改账户信息${NC}"
        echo -e "${PURPLE}➤ 5. 更新应用程序            ${RED}➤ 0. 退出系统${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}请选择操作 [0-4]:${NC}"
        read option
        
        case $option in
            1)
                parse_config
                
                echo -e "\n${YELLOW}=== 🛠️ 调试信息 ===${NC}"
                echo "🏷️ HOST: $HOST"
                echo "🔌 PORT: $PORT"
                echo "👤 USER: $USER"
                echo "🖥️ SERVER: $SERVER"
    
                # 建立本地隧道 🔄
                echo -e "\n${YELLOW}=== 🔗 本地隧道建立 ===${NC}"
                
                establish_tunnel 8002
                establish_tunnel 8001
                
                # 最终验证 🔄
                echo -e "\n${YELLOW}=== 🧪 最终验证 ===${NC}"      
                
                echo -e "\n🔧 后端服务状态："
                check_port 8002
                echo -e "\n🖥️ 前端服务状态："
                check_port 8001
                
                echo -e "\n🚨 访问测试："
                echo -e "${GREEN}🔧 后端服务：${NC}curl -I http://localhost:8002"
                echo -e "${GREEN}🌐 前端界面：${NC}打开浏览器访问 http://localhost:8001"
    
                # 启动应用
                echo -e "\n${CYAN}🚀 正在启动应用...${NC}"
                cd $TTS_dir
                source venv/bin/activate
                python3 main.py
                deactivate
    
                read -p "按回车键返回主菜单..."
                ;;
    
            2)
                parse_config
                
                echo -e "\n${YELLOW}=== 📂 文件同步 ===${NC}"
                ssh-keygen -R "[$HOST]:$PORT" >/dev/null 2>&1
                sync_roles
    
                read -p "按回车键返回主菜单..."
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
                
                # 使用双引号包裹表达式，并转义内部变量
                yq -i "
                  .ssh.host = \"$host\" |
                  .ssh.port = \"$port\"
                " "$config_file"
                
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
                
                yq -i "
                  .ssh.username = \"$username\" |
                  .ssh.password = \"$password\"
                " "$config_file"
                
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
                cd $TTS_dir
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

deploy
show_menu 
