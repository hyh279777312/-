import express from 'express';
import { createServer as createViteServer } from 'vite';
import path from 'path';
import { fileURLToPath } from 'url';
import { spawn } from 'child_process';
import fs from 'fs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

async function startServer() {
  const app = express();
  app.use(express.json());

  const PORT = process.env.PORT || 3000;
  const isProd = process.env.NODE_ENV === 'production';

  // API Routes
  app.post('/api/run-script', async (req, res) => {
    const { projectDir, customOutputDir } = req.body;
    if (!projectDir || !fs.existsSync(projectDir)) {
      return res.status(400).json({ success: false, error: '无效的工程文件夹路径' });
    }

    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');

    const scriptPath = path.join(__dirname, 'scripts/jianying_pack_v3.8.sh');
    const args = [scriptPath, projectDir];
    if (customOutputDir) {
      args.push(customOutputDir);
    }
    const child = spawn('bash', args);

    let fullOutput = '';

    child.stdout.on('data', (data) => {
      const text = data.toString();
      fullOutput += text;
      res.write(`data: ${JSON.stringify({ type: 'log', data: text })}\n\n`);
    });

    child.stderr.on('data', (data) => {
      const text = data.toString();
      fullOutput += text;
      res.write(`data: ${JSON.stringify({ type: 'log', data: text })}\n\n`);
    });

    child.on('close', (code) => {
      const match = fullOutput.match(/OUTPUT_DIR=(.+)/);
      const outputDir = match ? match[1].trim() : (customOutputDir || null);

      res.write(`data: ${JSON.stringify({ type: 'done', code, outputDir, success: code === 0 && Boolean(outputDir) })}\n\n`);
      res.end();
    });
  });

  app.post('/api/open-folder', (req, res) => {
    const { folderPath } = req.body;
    if (!folderPath || !fs.existsSync(folderPath)) {
      return res.status(400).json({ success: false, error: '文件夹路径不存在' });
    }
    const child = spawn('open', [folderPath]);
    child.on('close', (code) => {
      res.json({ success: code === 0 });
    });
  });

  app.post('/api/select-folder-applescript', async (req, res) => {
    const promptText = req.body.title || '选择【剪映 Mac 工程文件夹】';
    
    const checkOsascript = spawn('which', ['osascript']);
    checkOsascript.on('close', (code) => {
      if (code !== 0) {
        return res.json({ 
          success: false, 
          error: '当前云端预览环境非 macOS，无法弹出本地 Finder 弹窗。请在打包后的 macOS App 中使用，或直接输入路径。' 
        });
      }

      const script = `
        try
          set f to choose folder with prompt "${promptText}"
          POSIX path of f
        on error
          return ""
        end try
      `;
      const child = spawn('osascript', ['-e', script]);
      let result = '';
      child.stdout.on('data', (data) => { result += data.toString(); });
      child.on('close', (exitCode) => {
        const pathStr = result.trim();
        if (pathStr) {
          res.json({ success: true, path: pathStr.replace(/\/$/, '') });
        } else {
          res.json({ success: false, path: null });
        }
      });
    });
  });

  // Generate One-Click .command script for users to package App & DMG with mirrors
  app.get('/api/generate-command-script', (req, res) => {
    const commandContent = `#!/bin/bash
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
npm run electron:build

echo ""
echo "============================================================"
echo "打包完成！安装包 (.app 及 .dmg) 已生成在 release 目录中。"
echo "============================================================"
if [ -d "release" ]; then
    open "release"
fi
read -r -p "按回车关闭..." _
`;
    const filePath = path.join(__dirname, '一键打包App和DMG.command');
    fs.writeFileSync(filePath, commandContent, { mode: 0o755 });
    res.json({ success: true, message: '一键打包Command文件已在项目根目录生成！', path: filePath });
  });

  // Vite setup for development or static serving for production
  if (!isProd) {
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: 'spa',
    });
    app.use(vite.middlewares);
  } else {
    app.use(express.static(path.join(__dirname, 'dist')));
    app.get('*', (req, res) => {
      res.sendFile(path.join(__dirname, 'dist/index.html'));
    });
  }

  app.listen(Number(PORT), '0.0.0.0', () => {
    console.log(`Server running on http://localhost:${PORT}`);
  });
}

startServer();
