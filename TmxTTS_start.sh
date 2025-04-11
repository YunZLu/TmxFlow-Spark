#!/bin/bash
# 定义Ubuntu的安装目录路径
current_dir=$(pwd)
TTS_dir="$current_dir/TmxFlow-Spark"
backend_url="https://ixfjmr--8002.ap-beijing.cloudstudio.work/speak"
declare -i port=5000

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
            [ ! -x "$(command -v python3)" ] && missing+=("python3")
            
            # 安装基础依赖
            if [ ${#missing[@]} -gt 0 ]; then
                echo -e "${YELLOW}⚠️ 缺少依赖: ${missing[*]}${NC}"
                apt update -y && apt install -y "${missing[@]}"
            fi
        
            # 检查Python venv模块
            if ! python3 -c "import ensurepip; import venv" &>/dev/null; then
                echo -e "${YELLOW}⚠️ 缺少Python venv模块，尝试安装python3.12-venv${NC}"
                apt install -y python3.12-venv || {
                    echo -e "${RED}安装python3.12-venv失败，请检查系统源或手动安装${NC}"
                    exit 1
                }
            fi
        
            # 单独处理 lolcat 安装
            if ! command -v lolcat &>/dev/null; then
                echo -e "${YELLOW}⚠️ 缺少依赖: lolcat${NC}"
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


# 公共函数定义
check_status() {
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ 成功${NC}"
  else
    echo -e "${RED}❌ 失败${NC}"
  fi
}


# 启动界面
show_menu() {

    cd $current_dir
    while true; do
        clear
        cat $TTS_dir/TMX_logo.txt | lolcat 
        echo -e "${BLUE}\n════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}➤ 1. 启动应用程序            ${YELLOW}➤ 2. 修改服务器地址${NC}"
        echo -e "${PURPLE}➤ 3. 更新应用程序            ${RED}➤ 0. 退出系统${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}请选择操作 [0-4]:${NC}"
        read option
        
        case $option in
            1)
                # 启动应用
                echo -e "\n${CYAN}🚀 正在启动应用...${NC}"
                cd $TTS_dir
                source venv/bin/activate
                echo -e "\n${YELLOW}⏰ 执行命令: python3 main.py --backend_url $backend_url --port $port${NC}"
                python3 main.py --backend_url $backend_url --port $port
                deactivate
    
                read -p "⏎ 按回车键返回主菜单..."
                ;;
            2)
                if [ -n "$backend_url" ]; then
                    echo -e "${YELLOW}🛠️ 当前服务器地址: ${BLUE}$backend_url${NC}"
                    echo -e "${YELLOW}\n🔧 是否要修改? [Y/n]${NC}"
                    read confirm
                else
                    confirm="Y"
                fi
                
                if [[ $confirm =~ ^[Yy]$ || $confirm == "" ]]; then
                    echo -e "${YELLOW}🌐 请输入新的服务器地址:${NC}"
                    read new_url
                    
                    # 处理URL逻辑
                    processed_url="$new_url"
                    
                    # 判断是否为腾讯云地址（同时包含 .ap 和 work）
                    if [[ $processed_url == *".ap"* && $processed_url == *"work"* ]]; then
                        # 插入端口号（仅在 .ap 前无 -- 时添加）
                        if [[ $processed_url == *".ap"* ]]; then
                            if ! echo "$processed_url" | grep -qE ".*--.*\.ap"; then
                                processed_url=$(echo "$processed_url" | sed 's/\.ap/--8002.ap/')
                            fi
                        fi
                        # 强制替换路径为 /work/speak
                        processed_url=$(echo "$processed_url" | sed 's|work/.*|work/speak|')
                    else
                        echo -e "${YELLOW}⚠️ 非标准腾讯云地址，保留原始路径${NC}"
                    fi
                    
                    backend_url=$processed_url
                    
                    sed -i -E "s|^backend_url[[:space:]]*=.*|backend_url=\"${processed_url//&/\\&}\"|" "$current_dir/$0"
                    echo -e "${GREEN}\n✅ 配置更新成功: ${BLUE}$processed_url\n${NC}"
                else
                    echo -e "${YELLOW}🚫 已保留原始配置\n${NC}"
                fi
                read -p "⏎ 按回车键返回主菜单..."
                ;;
            3)
                echo -e "\n${CYAN}🔄 正在更新应用程序...${NC}"
                cd $TTS_dir
                git pull origin Tencent_CS && echo -e "\n${GREEN}✅ 应用程序已更新${NC}\n"
                echo -e "${YELLOW}按回车键返回主菜单...${NC}"
                read
                ;;
            0)
                echo -e "\n${YELLOW}👋 正在退出系统...${NC}\n"
                exit 0
                ;;
            *)
                echo -e "${RED}⚠️ 无效选项，请重新输入！${NC}\n"
                read -p "⏎ 按回车键返回主菜单..."
                ;;
        esac
    done
}

deploy
show_menu 
