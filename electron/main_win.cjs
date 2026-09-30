const { app, BrowserWindow, ipcMain, dialog, shell } = require('electron');
const path = require('path');
const { spawn } = require('child_process');
const fs = require('fs');

let mainWindow;

function getEmbeddedPythonPath() {
  const isPackaged = app.isPackaged;
  if (isPackaged) {
    const candidates = [
      path.join(path.dirname(process.execPath), 'resources', 'app.asar.unpacked', 'python', 'python.exe'),
      path.join(app.getAppPath(), '..', 'app.asar.unpacked', 'python', 'python.exe'),
      path.join(app.getAppPath(), 'python', 'python.exe'),
      path.join(process.resourcesPath, 'python', 'python.exe')
    ];
    for (const p of candidates) {
      if (fs.existsSync(p)) return p;
    }
  } else {
    const localPath = path.join(app.getAppPath(), 'python', 'python.exe');
    if (fs.existsSync(localPath)) return localPath;
  }
  return 'python'; // Fallback to system python
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 760,
    height: 560,
    minWidth: 680,
    minHeight: 500,
    title: '火枪手剪映工程迁移 V4.0.3 (Windows版)',
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
  if (process.platform !== 'win32') app.quit();
});

// IPC Handlers for Windows Native Dialogs and Operations
ipcMain.handle('dialog:open-directory', async (event, title) => {
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ['openDirectory'],
    title: title || '选择【剪映 Windows 工程文件夹】',
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

ipcMain.handle('run-packager', async (event, { projectDir, customOutputDir }) => {
  return new Promise((resolve, reject) => {
    const scriptName = 'jianying_pack_win.py';
    const sourceScript = path.join(app.getAppPath(), 'scripts', scriptName);
    const targetScript = path.join(app.getPath('userData'), scriptName);
    try {
      if (!fs.existsSync(path.dirname(targetScript))) {
        fs.mkdirSync(path.dirname(targetScript), { recursive: true });
      }
      fs.copyFileSync(sourceScript, targetScript);
    } catch (e) {
      console.error('Failed to prepare Windows packager script:', e);
    }

    const pythonBin = getEmbeddedPythonPath();
    const args = [targetScript, projectDir];
    if (customOutputDir) {
      args.push(customOutputDir);
    }

    const child = spawn(pythonBin, args, { shell: true });

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
        error: code !== 0 ? errorOutput || 'Windows 打包脚本执行出错' : null,
      });
    });
  });
});

ipcMain.handle('run-rebatch', async (event, { packageDir }) => {
  return new Promise((resolve, reject) => {
    const scriptName = 'jianying_rebatch_win.py';
    const sourceScript = path.join(app.getAppPath(), 'scripts', scriptName);
    const targetScript = path.join(app.getPath('userData'), scriptName);
    try {
      if (!fs.existsSync(path.dirname(targetScript))) {
        fs.mkdirSync(path.dirname(targetScript), { recursive: true });
      }
      fs.copyFileSync(sourceScript, targetScript);
    } catch (e) {
      console.error('Failed to prepare Windows rebatch script:', e);
    }

    const pythonBin = getEmbeddedPythonPath();
    const child = spawn(pythonBin, [targetScript, packageDir], { shell: true });

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
        error: code !== 0 ? errorOutput || 'Windows 回批脚本执行出错' : null,
      });
    });
  });
});
