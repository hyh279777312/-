@echo off
chcp 65001 >nul
setlocal

echo ============================================================
echo HQS 剪映工程收集 V4.0.3 - Windows 一键打包工具
echo ============================================================
echo.

echo [1/6] Checking Node.js...
where node >nul 2>&1
if %errorlevel% neq 0 (
echo.
echo ============================================================
echo 错误：未找到 Node.js，请先前往 https://nodejs.org/ 安装 Node.js
echo ============================================================
pause
exit /b 1
)

node --version
npm --version
echo.

echo [2/6] Checking embedded Python...
if not exist "python\python.exe" (
echo.
echo ============================================================
echo 错误：没有找到内置 Python！
echo.
echo 请确认以下文件存在：
echo python\python.exe
echo ============================================================
pause
exit /b 1
)

"python\python.exe" --version
if %errorlevel% neq 0 (
echo.
echo ============================================================
echo 错误：内置 Python 无法正常运行！
echo ============================================================
pause
exit /b 1
)

echo 内置 Python 检查通过。
echo.

echo [3/6] 正在配置国内镜像源 (npmmirror)...
call npm config set registry https://registry.npmmirror.com

set ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/
set ELECTRON_BUILDER_BINARIES_MIRROR=https://npmmirror.com/mirrors/electron-builder-binaries/

echo 国内镜像配置完成。
echo.

echo [4/6] 正在自动安装项目依赖...
call npm install --registry=https://registry.npmmirror.com

if %errorlevel% neq 0 (
echo.
echo ============================================================
echo 错误：npm install 依赖安装失败！
echo ============================================================
pause
exit /b 1
)

echo.
echo 项目依赖安装完成。
echo.

echo [5/6] 正在构建 React 前端...
call npm run build

if %errorlevel% neq 0 (
echo.
echo ============================================================
echo 错误：Vite 前端构建失败！
echo ============================================================
pause
exit /b 1
)

echo.
echo React 前端构建完成。
echo.

echo [6/6] 正在打包 Windows x64 Portable 单文件 EXE...
echo.
echo 内置 Python：
echo python\python.exe
echo.
echo 程序图标：
echo public\icon.png
echo.

call npx electron-builder --win portable --x64

if %errorlevel% neq 0 (
echo.
echo ============================================================
echo 错误：Windows Portable 单文件 EXE 打包失败！
echo ============================================================
pause
exit /b 1
)

echo.
echo ============================================================
echo 打包成功！
echo.
echo 单文件 EXE：
echo release\HQS剪映工程收集-v4.0.3-便携单文件.exe
echo.
echo ============================================================

if exist "release\HQS剪映工程收集-v4.0.3-便携单文件.exe" (
echo.
echo 已成功生成 Portable 单文件 EXE。
echo.
echo 文件位置：
echo %CD%\release\HQS剪映工程收集-v4.0.3-便携单文件.exe
echo.
start "" "release"
) else (
echo.
echo ============================================================
echo 警告：打包命令执行完成，但没有找到预期的 EXE 文件。
echo ============================================================
)

echo.
pause
endlocal
