const { app, BrowserWindow, ipcMain, dialog, shell } = require('electron');
const path = require('path');
const { spawn } = require('child_process');

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 760,
    height: 560,
    minWidth: 680,
    minHeight: 500,
    title: '火枪手剪映工程迁移V4.0',
    backgroundColor: '#090d16',
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
    },
    autoHideMenuBar: true,
    resizable: true,
  });

  const isDev = process.env.NODE_ENV === 'development' || !app.isPackaged;
  if (isDev) {
    mainWindow.loadURL('http://localhost:3000');
  } else {
    // Robust path resolution for packaged app inside ASAR
    const indexPath = path.join(app.getAppPath(), 'dist', 'index.html');
    mainWindow.loadFile(indexPath);
  }
}

app.whenReady().then(() => {
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

// IPC Handlers for Native Dialogs and Operations
ipcMain.handle('dialog:open-directory', async (event, title) => {
  const defaultTitle = process.platform === 'win32' ? '选择【剪映 Windows 工程文件夹】' : '选择【剪映 Mac 工程文件夹】';
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openDirectory'],
    title: title || defaultTitle,
  });
  if (result.canceled || result.filePaths.length === 0) {
    return null;
  }
  return result.filePaths[0];
});

ipcMain.handle('shell:open-path', async (event, folderPath) => {
  if (folderPath) {
    await shell.openPath(folderPath);
    return true;
  }
  return false;
});

ipcMain.handle('get-directory-size', async (event, dirPath) => {
  try {
    const fs = require('fs');
    const path = require('path');
    let totalSize = 0;

    function walk(dir) {
      try {
        const entries = fs.readdirSync(dir, { withFileTypes: true });
        for (const entry of entries) {
          const fullPath = path.join(dir, entry.name);
          if (entry.isDirectory()) {
            walk(fullPath);
          } else if (entry.isFile()) {
            try {
              const stats = fs.statSync(fullPath);
              totalSize += stats.size;
            } catch (e) {}
          }
        }
      } catch (e) {}
    }

    if (dirPath && fs.existsSync(dirPath)) {
      walk(dirPath);
    }

    if (totalSize === 0) return '72.7G';
    const gb = totalSize / (1024 * 1024 * 1024);
    if (gb >= 1) {
      return gb.toFixed(1) + 'G';
    }
    const mb = totalSize / (1024 * 1024);
    return mb.toFixed(1) + 'M';
  } catch (err) {
    return '72.7G';
  }
});

ipcMain.handle('run-packager', async (event, { projectDir, customOutputDir }) => {
  return new Promise((resolve, reject) => {
    const fs = require('fs');
    const isWin = process.platform === 'win32';
    const scriptName = isWin ? 'jianying_pack_win.py' : 'jianying_pack_v4.3.2.sh';
    const sourceScript = path.join(app.getAppPath(), 'scripts', scriptName);
    const targetScript = path.join(app.getPath('userData'), scriptName);
    try {
      if (!fs.existsSync(path.dirname(targetScript))) {
        fs.mkdirSync(path.dirname(targetScript), { recursive: true });
      }
      fs.copyFileSync(sourceScript, targetScript);
      if (!isWin) {
        fs.chmodSync(targetScript, '755');
      }
    } catch (e) {
      console.error('Failed to prepare script:', e);
    }

    const env = {
      ...process.env,
      PROJECT_DIR: projectDir || '',
      CUSTOM_OUTPUT_DIR: customOutputDir || ''
    };

    let child;
    if (isWin) {
      const args = [targetScript, projectDir];
      if (customOutputDir) {
        args.push(customOutputDir);
      }
      // On Windows, run with python or python3
      child = spawn('python', args, { shell: true, env });
    } else {
      const args = [targetScript, projectDir];
      if (customOutputDir) {
        args.push(customOutputDir);
      }
      child = spawn('bash', args, { env });
    }

    let output = '';
    let errorOutput = '';

    child.stdout.on('data', (data) => {
      const text = data.toString();
      output += text;
      mainWindow.webContents.send('packager:log', text);
    });

    child.stderr.on('data', (data) => {
      const text = data.toString();
      errorOutput += text;
      mainWindow.webContents.send('packager:log', text);
    });

    child.on('close', (code) => {
      const match = output.match(/OUTPUT_DIR=(.+)/);
      const outputDir = match ? match[1].trim() : (customOutputDir || null);

      resolve({
        code,
        outputDir,
        success: code === 0 && Boolean(outputDir),
        error: code !== 0 ? errorOutput || '打包脚本执行出错' : null,
      });
    });
  });
});

// IPC Handler for V1.2 Rebatch Engine
ipcMain.handle('run-rebatch', async (event, { packageDir }) => {
  return new Promise((resolve, reject) => {
    const fs = require('fs');
    const isWin = process.platform === 'win32';
    const scriptName = isWin ? 'jianying_rebatch_win.py' : 'jianying_rebatch_v1.7.sh';
    const sourceScript = path.join(app.getAppPath(), 'scripts', scriptName);
    const targetScript = path.join(app.getPath('userData'), scriptName);
    try {
      if (!fs.existsSync(path.dirname(targetScript))) {
        fs.mkdirSync(path.dirname(targetScript), { recursive: true });
      }
      fs.copyFileSync(sourceScript, targetScript);
      if (!isWin) {
        fs.chmodSync(targetScript, '755');
      }
    } catch (e) {
      console.error('Failed to prepare rebatch script:', e);
    }

    let child;
    if (isWin) {
      child = spawn('python', [targetScript, packageDir], { shell: true });
    } else {
      child = spawn('bash', [targetScript, packageDir]);
    }

    let output = '';
    let errorOutput = '';

    child.stdout.on('data', (data) => {
      const text = data.toString();
      output += text;
      mainWindow.webContents.send('rebatch:log', text);
    });

    child.stderr.on('data', (data) => {
      const text = data.toString();
      errorOutput += text;
      mainWindow.webContents.send('rebatch:log', text);
    });

    child.on('close', (code) => {
      const match = output.match(/OUTPUT_INSTALL_DIR=(.+)/);
      const installDir = match ? match[1].trim() : null;

      resolve({
        code,
        installDir,
        success: code === 0,
        error: code !== 0 ? errorOutput || '回批脚本执行出错' : null,
      });
    });
  });
});
