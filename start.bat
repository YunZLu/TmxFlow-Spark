@echo off
chcp 65001 >nul
set PYTHONIOENCODING=utf-8
setlocal enabledelayedexpansion

set "BAT_DIR=%~dp0"
cd /d "%BAT_DIR%"


REM 🎯 配置参数

set "backend_url="
set "port="

set "REQUIREMENTS_HASH=venv_requirements.md5"
set "VENV_DIR=venv"

:check_python
REM 🔍 增强版Python检测
echo 🔍 正在检查Python安装...
python -V >nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ 未检测到Python! 开始自动安装...
    
    REM 📥 下载安装包
    echo 🔄 正在下载Python 3.12.9安装程序...
    powershell -Command "Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.12.9/python-3.12.9-amd64.exe' -OutFile 'python_installer.exe'"
    
    if exist python_installer.exe (
        echo 🔄 正在静默安装Python...
        python_installer.exe /quiet InstallAllUsers=1 PrependPath=1 Include_test=0
        del python_installer.exe
        
        echo ✅ Python安装成功！
        echo ⚙️ 强制刷新环境变量...
        
        REM 🔄 深度路径检测
        set "python_dir="
        for %%d in (
            "HKLM\SOFTWARE\Python\PythonCore\3.12.9\InstallPath",
            "HKLM\SOFTWARE\WOW6432Node\Python\PythonCore\3.12.9\InstallPath"
        ) do (
            for /f "tokens=2,*" %%A in ('reg query "%%~d" /ve 2^>nul ^| find "REG_SZ"') do (
                if not defined python_dir set "python_dir=%%B"
            )
        )
        
        REM 🗺️ 备用路径检测
        if not defined python_dir (
            for %%d in (
                "C:\Program Files\Python312",
                "C:\Program Files (x86)\Python312"
            ) do if exist "%%~d\python.exe" set "python_dir=%%~d"
        )
        
        if defined python_dir (
            echo 🔄 检测到Python路径: !python_dir!
            set "PATH=!python_dir!;!python_dir!\Scripts;%PATH%"
            where python
            goto check_python
        ) else (
            echo ❌ 自动路径检测失败，请手动运行以下命令后重试：
            echo SET PATH=%%PATH%%;C:\Python安装路径
            exit /b 1
        )
    ) else (
        echo ❌ Python安装包下载失败
        exit /b 1
    )
)

REM ⚙️ 验证Python路径
echo ✅ 当前Python路径：
where python

:check_venv
REM 🛡️ 增强虚拟环境验证
if exist "%VENV_DIR%\" (
    echo 🔍 深度验证虚拟环境完整性...
    
    REM 检查关键文件存在性
    set "missing_file=0"
    for %%f in (
        "%VENV_DIR%\Scripts\activate.bat",
        "%VENV_DIR%\Scripts\python.exe",
        "%VENV_DIR%\Scripts\pip.exe"
    ) do if not exist "%%~f" set "missing_file=1"
    
    REM 验证Python可执行性
    if !missing_file! equ 0 (
        "%VENV_DIR%\Scripts\python.exe" -c "exit(0)" >nul 2>&1
        if !errorlevel! neq 0 set "missing_file=1"
    )
    
    if !missing_file! equ 1 (
        echo ⚠️ 虚拟环境不完整，需要重建
        rmdir /s /q "%VENV_DIR%" 2>nul
        goto create_venv
    ) else (
        echo ✅ 虚拟环境完整可用
        goto check_dependencies
    )
) else (
    echo 🛠️ 未检测到虚拟环境
    goto create_venv
)

:create_venv
echo 🛠️ 正在创建虚拟环境...
python -m venv "%VENV_DIR%"
if %errorlevel% neq 0 (
    echo ❌ 虚拟环境创建失败
    exit /b 1
)
echo ✅ 虚拟环境创建成功
set "FORCE_INSTALL=1"

:check_dependencies
REM 🔄 智能依赖安装检测
if exist "requirements.txt" (
    echo 🔍 检查依赖变更...
    
    REM 生成当前哈希
    certutil -hashfile requirements.txt MD5 | find /v ":" > "%REQUIREMENTS_HASH%.tmp"
    
    REM 比对历史哈希
    set "NEED_INSTALL=1"
    if exist "%REQUIREMENTS_HASH%" (
        fc "%REQUIREMENTS_HASH%" "%REQUIREMENTS_HASH%.tmp" >nul 2>&1
        if !errorlevel! equ 0 set "NEED_INSTALL=0"
    )
    
    if defined FORCE_INSTALL set "NEED_INSTALL=1"
    
    if !NEED_INSTALL! equ 1 (
        echo 📦 正在安装/更新依赖...
        call "%VENV_DIR%\Scripts\activate.bat"
        pip install -r requirements.txt -i https://mirrors.aliyun.com/pypi/simple/
        if !errorlevel! neq 0 (
            echo ❌ 依赖安装失败
            exit /b 1
        )
        move /Y "%REQUIREMENTS_HASH%.tmp" "%REQUIREMENTS_HASH%" >nul
        echo ✅ 依赖状态已更新
    ) else (
        echo ✅ 依赖项未变更，跳过安装
        del "%REQUIREMENTS_HASH%.tmp" 2>nul
    )
)

:launch
REM 🚀 启动应用程序
call "%VENV_DIR%\Scripts\activate.bat"
set "launch_args="
if defined backend_url (
    if not "!backend_url:.ap=!" == "!backend_url!" (
        if not "!backend_url:.work=!" == "!backend_url!" (
            if "!backend_url:--=!" == "!backend_url!" (
                echo 检测到腾讯云地址，正在处理...
                set "backend_url=!backend_url:.ap=--8002.ap!"
                set "temp=!backend_url:.work=#!"
                rem 分割出.work前的域名部分
                for /f "tokens=1 delims=#" %%a in ("!temp!") do set "base=%%a"
                rem 拼接目标路径
                set "backend_url=!base!.work/speak"
                
            ) else (
                set "temp=!backend_url:.work=#!"
                rem 分割出.work前的域名部分
                for /f "tokens=1 delims=#" %%a in ("!temp!") do set "base=%%a"
                rem 拼接目标路径
                set "backend_url=!base!.work/speak"
            )
        )
    )
)

if not "!backend_url!"=="" set "launch_args=--backend_url !backend_url!"
if not "%port%"=="" set "launch_args=!launch_args! --port %port%"

echo 🚀 正在启动应用，命令：python main.py %launch_args%
if defined launch_args (
    python main.py %launch_args%
) else (
    python main.py
)
endlocal
