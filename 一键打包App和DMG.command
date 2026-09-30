#!/bin/bash
cd "$(dirname "$0")"

echo "============================================================"
echo "HQS 剪映工程收集 V4.0.3 - macOS 一键打包工具"
echo "支持 macOS 12 (Monterey) ~ 15 (Sequoia) [Intel & Apple Silicon]"
echo "============================================================"

if ! command -v node &> /dev/null; then
    echo "错误：未找到 Node.js，请先前往 https://nodejs.org/ 安装 Node.js"
    read -r -p "按回车退出..." _
    exit 1
fi

echo "1. 正在优先配置国内镜像源 (npmmirror)..."
npm config set registry https://registry.npmmirror.com
export ELECTRON_MIRROR="https://npmmirror.com/mirrors/electron/"
export ELECTRON_BUILDER_BINARIES_MIRROR="https://npmmirror.com/mirrors/electron-builder-binaries/"

echo "2. 正在自动安装项目依赖（根目录同步安装）..."
npm install --registry=https://registry.npmmirror.com

echo "3. 正在执行 React 前端构建与 Electron-Builder 打包 (.app & .dmg)..."
if npm run electron:build; then
    echo ""
    echo "============================================================"
    echo "打包成功！"
    echo "安装包 (.app / .dmg) 已生成在 release 目录中。"
    echo "============================================================"
    if [ -d "release" ]; then
        open "release"
    fi
else
    echo ""
    echo "============================================================"
    echo "打包失败！"
    echo "请检查上面的错误信息。"
    echo "============================================================"
    read -r -p "按回车退出..." _
    exit 1
fi

read -r -p "按回车关闭..." _
