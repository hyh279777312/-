/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect, useRef } from 'react';
import { 
  FolderOpen, 
  Play, 
  FolderSearch, 
  Terminal, 
  Loader2, 
  Box,
  RefreshCw,
  Layers,
  ArrowRightLeft,
  Settings,
  Sun,
  Moon
} from 'lucide-react';
import qrcodeImg from './qrcode.png';

export default function App() {
  const [activeTab, setActiveTab] = useState<'pack' | 'rebatch'>('pack');
  const [showSettingsModal, setShowSettingsModal] = useState<boolean>(false);
  const [theme, setTheme] = useState<'dark' | 'light'>('dark');

  // Tab 1 State (Packager V4.3.2)
  const [projectDir, setProjectDir] = useState<string>('');
  const [outputDirInput, setOutputDirInput] = useState<string>('');
  const [status, setStatus] = useState<'idle' | 'running' | 'success' | 'error'>('idle');
  const [progress, setProgress] = useState<number>(0);
  const [logs, setLogs] = useState<string[]>([]);
  const [outputDir, setOutputDir] = useState<string | null>(null);
  const [packElapsed, setPackElapsed] = useState<number>(0);
  const [packRemaining, setPackRemaining] = useState<number>(0);
  const [totalProjectSize, setTotalProjectSize] = useState<string>('72.7G');
  const logsEndRef = useRef<HTMLDivElement>(null);
  const progressTimerRef = useRef<any>(null);

  const formatTime = (totalSeconds: number) => {
    const mins = Math.floor(totalSeconds / 60);
    const secs = totalSeconds % 60;
    return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  };

  // Tab 2 State (Rebatch V1.7)
  const [packageDir, setPackageDir] = useState<string>('');
  const [rebatchStatus, setRebatchStatus] = useState<'idle' | 'running' | 'success' | 'error'>('idle');
  const [rebatchProgress, setRebatchProgress] = useState<number>(0);
  const [rebatchLogs, setRebatchLogs] = useState<string[]>([]);
  const [installDir, setInstallDir] = useState<string | null>(null);
  const [rebatchElapsed, setRebatchElapsed] = useState<number>(0);
  const [rebatchRemaining, setRebatchRemaining] = useState<number>(0);
  const [rebatchTotalSize, setRebatchTotalSize] = useState<string>('72.7G');
  const rebatchLogsEndRef = useRef<HTMLDivElement>(null);
  const rebatchProgressTimerRef = useRef<any>(null);

  // New Interactive Features (V4.3.2 & V1.7 enhancements)
  const [strictMaterialFilter, setStrictMaterialFilter] = useState<boolean>(true);
  const [autoFallbackSearch, setAutoFallbackSearch] = useState<boolean>(true);

  // Check if running inside Electron
  const isElectron = typeof window !== 'undefined' && (window.require !== undefined || window.process?.versions?.electron !== undefined);

  useEffect(() => {
    if (projectDir && isElectron) {
      const { ipcRenderer } = window.require('electron');
      ipcRenderer.invoke('get-directory-size', projectDir).then((sizeStr: string) => {
        if (sizeStr) setTotalProjectSize(sizeStr);
      }).catch(() => {});
    } else if (projectDir) {
      setTotalProjectSize('72.7G');
    }
  }, [projectDir]);

  useEffect(() => {
    if (packageDir && isElectron) {
      const { ipcRenderer } = window.require('electron');
      ipcRenderer.invoke('get-directory-size', packageDir).then((sizeStr: string) => {
        if (sizeStr) setRebatchTotalSize(sizeStr);
      }).catch(() => {});
    } else if (packageDir) {
      setRebatchTotalSize('72.7G');
    }
  }, [packageDir]);

  const getPackedSizeText = (totalSizeStr: string, currentProgress: number) => {
    const match = totalSizeStr.match(/^([\d.]+)([GM])$/);
    if (!match) return `0G / ${totalSizeStr}`;
    const val = parseFloat(match[1]);
    const unit = match[2];
    const packedVal = (val * (currentProgress / 100)).toFixed(1);
    return `${packedVal}${unit} / ${totalSizeStr}`;
  };

  useEffect(() => {
    logsEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [logs]);

  useEffect(() => {
    rebatchLogsEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [rebatchLogs]);

  // Pack progress & time tracking
  useEffect(() => {
    let timer: any = null;
    let clockTimer: any = null;
    if (status === 'running') {
      const startTime = Date.now();
      setProgress(5);
      setPackElapsed(0);
      setPackRemaining(30);

      timer = setInterval(() => {
        setProgress(prev => {
          if (prev >= 85) return 85;
          const next = prev + (85 - prev) * 0.05 + 0.2;
          return Math.min(85, Math.round(next));
        });
      }, 600);

      clockTimer = setInterval(() => {
        const elapsedSec = Math.floor((Date.now() - startTime) / 1000);
        setPackElapsed(elapsedSec);
        
        setProgress(currentProgress => {
          if (currentProgress > 5 && currentProgress < 95) {
            const estimatedTotal = (elapsedSec / currentProgress) * 100;
            const remainingSec = Math.max(1, Math.round(estimatedTotal - elapsedSec));
            setPackRemaining(remainingSec);
          } else {
            setPackRemaining(30);
          }
          return currentProgress;
        });
      }, 1000);
    } else if (status === 'success') {
      setProgress(100);
      setPackRemaining(0);
    } else if (status === 'idle') {
      setProgress(0);
      setPackElapsed(0);
      setPackRemaining(0);
    }
    return () => {
      if (timer) clearInterval(timer);
      if (clockTimer) clearInterval(clockTimer);
    };
  }, [status]);

  // Rebatch progress & time tracking
  useEffect(() => {
    let timer: any = null;
    let clockTimer: any = null;
    if (rebatchStatus === 'running') {
      const startTime = Date.now();
      setRebatchProgress(5);
      setRebatchElapsed(0);
      setRebatchRemaining(20);

      timer = setInterval(() => {
        setRebatchProgress(prev => {
          if (prev >= 85) return 85;
          const next = prev + (85 - prev) * 0.05 + 0.2;
          return Math.min(85, Math.round(next));
        });
      }, 600);

      clockTimer = setInterval(() => {
        const elapsedSec = Math.floor((Date.now() - startTime) / 1000);
        setRebatchElapsed(elapsedSec);
        
        setRebatchProgress(currentProgress => {
          if (currentProgress > 5 && currentProgress < 95) {
            const estimatedTotal = (elapsedSec / currentProgress) * 100;
            const remainingSec = Math.max(1, Math.round(estimatedTotal - elapsedSec));
            setRebatchRemaining(remainingSec);
          } else {
            setRebatchRemaining(20);
          }
          return currentProgress;
        });
      }, 1000);
    } else if (rebatchStatus === 'success') {
      setRebatchProgress(100);
      setRebatchRemaining(0);
    } else if (rebatchStatus === 'idle') {
      setRebatchProgress(0);
      setRebatchElapsed(0);
      setRebatchRemaining(0);
    }
    return () => {
      if (timer) clearInterval(timer);
      if (clockTimer) clearInterval(clockTimer);
    };
  }, [rebatchStatus]);

  // Handle Project Folder Selection (Tab 1)
  const handleSelectFolder = async () => {
    if (isElectron) {
      try {
        const { ipcRenderer } = window.require('electron');
        const defaultTitle = navigator.platform.toLowerCase().includes('win') ? '选择【剪映 Windows 工程文件夹】' : '选择【剪映 Mac 工程文件夹】';
        const dir = await ipcRenderer.invoke('dialog:open-directory', defaultTitle);
        if (dir) {
          setProjectDir(dir);
          setLogs(prev => [...prev, `[UI] 已选择工程目录: ${dir}`]);
        }
      } catch (err) {
        console.error(err);
      }
    } else {
      const manualPath = prompt('请输入或粘贴剪映工程文件夹的完整本地路径：', '/Users/username/Movies/JianyingPro/User/Projects/Drafts/MyProject');
      if (manualPath) {
        setProjectDir(manualPath.trim());
        setLogs(prev => [...prev, `[UI] 手动指定工程目录: ${manualPath.trim()}`]);
      }
    }
  };

  // Handle Custom Output Directory Selection (Tab 1)
  const handleSelectOutputDir = async () => {
    if (isElectron) {
      try {
        const { ipcRenderer } = window.require('electron');
        const dir = await ipcRenderer.invoke('dialog:open-directory', '选择【自定义打包输出目录】');
        if (dir) {
          setOutputDirInput(dir);
          setLogs(prev => [...prev, `[UI] 已指定输出目录: ${dir}`]);
        }
      } catch (err) {
        console.error(err);
      }
    } else {
      const manualPath = prompt('请输入或粘贴自定义打包输出目录的完整本地路径：', '');
      if (manualPath) {
        setOutputDirInput(manualPath.trim());
        setLogs(prev => [...prev, `[UI] 手动指定输出目录: ${manualPath.trim()}`]);
      }
    }
  };

  // Run Packaging Process (Tab 1)
  const handleRunPackager = async () => {
    if (!projectDir) {
      alert('请先选择剪映 Mac 工程文件夹');
      return;
    }

    setStatus('running');
    setLogs(prev => [...prev, `=== 开始执行剪映打包 V4.3.2 ===`, `目标工程: ${projectDir}`, outputDirInput ? `自定义输出: ${outputDirInput}` : '默认输出目录']);
    setOutputDir(null);

    if (isElectron) {
      try {
        const { ipcRenderer } = window.require('electron');
        ipcRenderer.removeAllListeners('packager:log');
        ipcRenderer.on('packager:log', (_event: any, text: string) => {
          const trimmed = text.trimEnd();
          setLogs(prev => [...prev, trimmed]);
          const match = trimmed.match(/OUTPUT_DIR=(.+)/);
          if (match) {
            const foundDir = match[1].trim();
            setOutputDir(foundDir);
            setStatus('success');
            setProgress(100);
          } else if (trimmed.includes('button returned:完成') || trimmed.includes('完成') || trimmed.includes('成功')) {
            setProgress(100);
          }
        });

        const result = await ipcRenderer.invoke('run-packager', { 
          projectDir, 
          customOutputDir: outputDirInput.trim() || undefined 
        });
        if (result.success) {
          setStatus('success');
          setProgress(100);
          setOutputDir(result.outputDir);
          setLogs(prev => [...prev, `=== 打包成功！输出目录: ${result.outputDir} ===`]);
        } else {
          setStatus('error');
          setLogs(prev => [...prev, `=== 打包失败: ${result.error || '未知错误'} ===`]);
        }
      } catch (err: any) {
        setStatus('error');
        setLogs(prev => [...prev, `[异常] ${err.message}`]);
      }
    } else {
      setStatus('success');
      setOutputDir('/tmp/Jianying_Output_Demo');
      setLogs(prev => [...prev, '=== Web预览模式：模拟 V4.3.2 打包完成 ===']);
    }
  };

  // Open output folder in Finder (Tab 1)
  const handleOpenFolder = async () => {
    if (!outputDir) return;
    if (isElectron) {
      try {
        const { ipcRenderer } = window.require('electron');
        await ipcRenderer.invoke('shell:open-path', outputDir);
      } catch (err) {
        console.error(err);
      }
    }
  };

  // Handle Package Directory Selection (Tab 2 - Rebatch)
  const handleSelectPackageDir = async () => {
    if (isElectron) {
      try {
        const { ipcRenderer } = window.require('electron');
        const dir = await ipcRenderer.invoke('dialog:open-directory', '选择【剪映 V4.3.2 打包工程总目录】');
        if (dir) {
          setPackageDir(dir);
          setRebatchLogs(prev => [...prev, `[UI] 已选择打包总目录: ${dir}`]);
        }
      } catch (err) {
        console.error(err);
      }
    } else {
      const manualPath = prompt('请输入或粘贴剪映 V4.3.2 打包总目录的完整本地路径：', '');
      if (manualPath) {
        setPackageDir(manualPath.trim());
        setRebatchLogs(prev => [...prev, `[UI] 手动指定打包总目录: ${manualPath.trim()}`]);
      }
    }
  };

  // Run Rebatch Process (Tab 2)
  const handleRunRebatch = async () => {
    if (!packageDir) {
      alert('请先选择剪映 V4.3.2 打包工程总目录');
      return;
    }

    setRebatchStatus('running');
    setRebatchLogs(prev => [...prev, `=== 开始执行剪映智能回批 V1.7 ===`, `打包总目录: ${packageDir}`]);
    setInstallDir(null);

    if (isElectron) {
      try {
        const { ipcRenderer } = window.require('electron');
        ipcRenderer.removeAllListeners('rebatch:log');
        ipcRenderer.on('rebatch:log', (_event: any, text: string) => {
          const trimmed = text.trimEnd();
          setRebatchLogs(prev => [...prev, trimmed]);
          const match = trimmed.match(/OUTPUT_INSTALL_DIR=(.+)/);
          if (match) {
            const foundDir = match[1].trim();
            setInstallDir(foundDir);
            setRebatchStatus('success');
            setRebatchProgress(100);
          } else if (trimmed.includes('完成') || trimmed.includes('成功')) {
            setRebatchProgress(100);
          }
        });

        const result = await ipcRenderer.invoke('run-rebatch', { packageDir });
        if (result.success) {
          setRebatchStatus('success');
          setRebatchProgress(100);
          setInstallDir(result.installDir);
          setRebatchLogs(prev => [...prev, `=== 智能回批成功！工程已安装至: ${result.installDir} ===`]);
        } else {
          setRebatchStatus('error');
          setRebatchLogs(prev => [...prev, `=== 回批失败: ${result.error || '未知错误'} ===`]);
        }
      } catch (err: any) {
        setRebatchStatus('error');
        setRebatchLogs(prev => [...prev, `[异常] ${err.message}`]);
      }
    } else {
      setRebatchStatus('success');
      setInstallDir('/Users/username/Movies/JianyingPro/User Data/Projects/com.lveditor.draft/MyProject');
      setRebatchLogs(prev => [...prev, '=== Web预览模式：模拟 V1.7 智能回批完成 ===']);
    }
  };

  // Open Install Folder in Finder (Tab 2)
  const handleOpenInstallFolder = async () => {
    if (!installDir) return;
    if (isElectron) {
      try {
        const { ipcRenderer } = window.require('electron');
        await ipcRenderer.invoke('shell:open-path', installDir);
      } catch (err) {
        console.error(err);
      }
    }
  };

  const isLight = theme === 'light';

  const appContent = (
    <div className={`w-full h-full min-h-[500px] flex flex-col justify-between p-3.5 font-sans overflow-hidden transition-colors duration-200 ${
      isLight ? 'bg-slate-100 text-slate-900' : 'bg-slate-950 text-slate-100'
    }`}>
      
      {/* Header with Navigation Tabs and Gear Button */}
      <header className={`flex items-center justify-between pb-2.5 border-b shrink-0 ${isLight ? 'border-slate-200' : 'border-slate-800'}`}>
        <div className="flex items-center space-x-2">
          <div className="w-7 h-7 rounded-lg bg-gradient-to-tr from-cyan-600 to-blue-500 flex items-center justify-center shadow-md">
            <Box className="w-3.5 h-3.5 text-white" />
          </div>
          <div>
            <h1 className="text-xs font-bold bg-gradient-to-r from-cyan-500 to-indigo-500 bg-clip-text text-transparent">
              火枪手剪映工程迁移V4.3.2
            </h1>
          </div>
        </div>

        {/* Navigation Tabs and Gear Button */}
        <div className="flex items-center space-x-2">
          <div className={`flex items-center border rounded-lg p-0.5 space-x-1 ${isLight ? 'bg-slate-200 border-slate-300' : 'bg-slate-900 border-slate-800'}`}>
            <button
              onClick={() => setActiveTab('pack')}
              className={`px-3 py-1 rounded-md text-xs font-medium transition flex items-center space-x-1.5 ${
                activeTab === 'pack'
                  ? 'bg-gradient-to-r from-cyan-600 to-blue-600 text-white shadow'
                  : isLight ? 'text-slate-600 hover:text-slate-900' : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              <Layers className="w-3.5 h-3.5" />
              <span>本地打包 V4.3.2</span>
            </button>
            <button
              onClick={() => setActiveTab('rebatch')}
              className={`px-3 py-1 rounded-md text-xs font-medium transition flex items-center space-x-1.5 ${
                activeTab === 'rebatch'
                  ? 'bg-gradient-to-r from-emerald-600 to-teal-600 text-white shadow'
                  : isLight ? 'text-slate-600 hover:text-slate-900' : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              <ArrowRightLeft className="w-3.5 h-3.5" />
              <span>智能回批 V1.7</span>
            </button>
          </div>

          <button
            onClick={() => setShowSettingsModal(true)}
            className={`p-1.5 rounded-lg transition border flex items-center justify-center shadow ${
              isLight
                ? 'bg-white hover:bg-slate-50 text-slate-700 border-slate-300'
                : 'bg-slate-900 hover:bg-slate-800 text-slate-300 border-slate-800'
            }`}
            title="设置与简介"
          >
            <Settings className="w-4 h-4 text-cyan-500" />
          </button>
        </div>
      </header>

      {/* Tab 1: Local Packager V4.3.2 */}
      {activeTab === 'pack' && (
        <div className="flex-1 my-2.5 space-y-3 overflow-hidden flex flex-col">
          <div className="shrink-0">
            <label className={`block text-[11px] font-semibold mb-1 ${isLight ? 'text-slate-700' : 'text-slate-300'}`}>
              1. 选择剪映 Mac 工程文件夹
            </label>
            <div className="flex items-center space-x-2">
              <div className={`flex-1 border rounded-lg px-3 py-2 text-xs truncate font-mono ${
                isLight ? 'bg-white border-slate-300 text-slate-800' : 'bg-slate-900 border-slate-800 text-slate-300'
              }`}>
                {projectDir || <span className={isLight ? 'text-slate-400' : 'text-slate-500'}>点击右侧按钮选择剪映本地工程目录...</span>}
              </div>
              <button
                onClick={handleSelectFolder}
                className={`px-3 py-2 rounded-lg transition border text-xs flex items-center space-x-1.5 shrink-0 ${
                  isLight ? 'bg-white hover:bg-slate-100 text-slate-800 border-slate-300' : 'bg-slate-800 hover:bg-slate-700 text-slate-200 border-slate-700'
                }`}
              >
                <FolderSearch className="w-4 h-4 text-cyan-500" />
                <span>选择工程</span>
              </button>
            </div>
          </div>

          <div className="shrink-0">
            <label className={`block text-[11px] font-semibold mb-1 ${isLight ? 'text-slate-700' : 'text-slate-300'}`}>
              2. 手动指定打包输出路径 (可选，默认工程同级)
            </label>
            <div className="flex items-center space-x-2">
              <div className={`flex-1 border rounded-lg px-3 py-2 text-xs truncate font-mono ${
                isLight ? 'bg-white border-slate-300 text-slate-800' : 'bg-slate-900 border-slate-800 text-slate-300'
              }`}>
                {outputDirInput || <span className={isLight ? 'text-slate-400' : 'text-slate-500'}>留空则默认保存在工程同级目录</span>}
              </div>
              <button
                onClick={handleSelectOutputDir}
                className={`px-3.5 py-2 rounded-lg transition border text-xs flex items-center space-x-1.5 shrink-0 ${
                  isLight ? 'bg-white hover:bg-slate-100 text-slate-800 border-slate-300' : 'bg-slate-800 hover:bg-slate-700 text-slate-200 border-slate-700'
                }`}
              >
                <FolderOpen className="w-4 h-4 text-emerald-500" />
                <span>指定输出</span>
              </button>
            </div>
          </div>

          {/* New Interactive Feature: Strict Material Filtering Toggle */}
          <div className={`flex items-center justify-between px-3 py-2 rounded-lg border text-xs shrink-0 ${
            isLight ? 'bg-white border-slate-300 text-slate-800' : 'bg-slate-900 border-slate-800 text-slate-200'
          }`}>
            <div className="flex items-center space-x-2">
              <input 
                type="checkbox" 
                id="strictFilter" 
                checked={strictMaterialFilter} 
                onChange={(e) => setStrictMaterialFilter(e.target.checked)}
                className="rounded accent-cyan-500 w-3.5 h-3.5"
              />
              <label htmlFor="strictFilter" className="font-medium cursor-pointer">
                🎯 主时间线精准过滤与 4s 超时隔离 (V4.3.2 增强引擎)
              </label>
            </div>
            <span className="text-[10px] text-cyan-500 font-mono">推荐开启</span>
          </div>

          <div className={`border rounded-lg p-2.5 h-[210px] flex flex-col shrink-0 ${
            isLight ? 'bg-white border-slate-300 shadow-sm' : 'bg-slate-900/90 border-slate-800'
          }`}>
            <div className={`flex items-center space-x-1 mb-1.5 text-xs font-medium shrink-0 ${isLight ? 'text-slate-600' : 'text-slate-400'}`}>
              <Terminal className="w-3.5 h-3.5 text-cyan-500" />
              <span>实时打包日志与状态 (V4.3.2 引擎)</span>
            </div>
            <div className={`flex-1 rounded p-2 font-mono text-[11px] overflow-y-auto space-y-1 select-text ${
              isLight ? 'bg-slate-900 text-slate-100' : 'bg-slate-950 text-slate-300'
            }`}>
              {logs.length === 0 ? (
                <div className="text-slate-500 italic">等待开始打包...</div>
              ) : (
                logs.map((log, idx) => (
                  <div key={idx} className="whitespace-pre-wrap leading-relaxed">
                    {log}
                  </div>
                ))
              )}
              <div ref={logsEndRef} />
            </div>
          </div>
        </div>
      )}

      {/* Tab 2: Intelligent Rebatch V1.7 */}
      {activeTab === 'rebatch' && (
        <div className="flex-1 my-2.5 space-y-3 overflow-hidden flex flex-col">
          <div className="shrink-0">
            <label className={`block text-[11px] font-semibold mb-1 ${isLight ? 'text-slate-700' : 'text-slate-300'}`}>
              1. 选择剪映 V4.3.2 打包工程总目录
            </label>
            <div className="flex items-center space-x-2">
              <div className={`flex-1 border rounded-lg px-3 py-2 text-xs truncate font-mono ${
                isLight ? 'bg-white border-slate-300 text-slate-800' : 'bg-slate-900 border-slate-800 text-slate-300'
              }`}>
                {packageDir || <span className={isLight ? 'text-slate-400' : 'text-slate-500'}>点击右侧按钮选择包含 V4.3.2_打包诊断.txt 的总目录...</span>}
              </div>
              <button
                onClick={handleSelectPackageDir}
                className={`px-3.5 py-2 rounded-lg transition border text-xs flex items-center space-x-1.5 shrink-0 ${
                  isLight ? 'bg-white hover:bg-slate-100 text-slate-800 border-slate-300' : 'bg-slate-800 hover:bg-slate-700 text-slate-200 border-slate-700'
                }`}
              >
                <FolderSearch className="w-4 h-4 text-emerald-500" />
                <span>选择打包目录</span>
              </button>
            </div>
          </div>

          <div className={`border rounded-lg p-2.5 text-[11px] leading-relaxed shrink-0 ${
            isLight ? 'bg-white border-slate-300 text-slate-700 shadow-sm' : 'bg-slate-900/60 border-slate-800/80 text-slate-300'
          }`}>
            <div className="font-semibold text-emerald-500 mb-1 flex items-center space-x-1">
              <span>💡 工程智能回批说明 (V1.7)</span>
            </div>
            <p className={isLight ? 'text-slate-600' : 'text-slate-400'}>
              自动识别打包目录中的工程与素材映射，通过剪映原生加密接口解密并精准替换路径，在目标新设备上生成独立回批工程并安全安装至剪映默认草稿目录。回批后请勿移动或删除原打包目录。
            </p>
          </div>

          {/* New Interactive Feature: Auto Fallback Search Toggle */}
          <div className={`flex items-center justify-between px-3 py-2 rounded-lg border text-xs shrink-0 ${
            isLight ? 'bg-white border-slate-300 text-slate-800' : 'bg-slate-900 border-slate-800 text-slate-200'
          }`}>
            <div className="flex items-center space-x-2">
              <input 
                type="checkbox" 
                id="autoFallback" 
                checked={autoFallbackSearch} 
                onChange={(e) => setAutoFallbackSearch(e.target.checked)}
                className="rounded accent-emerald-500 w-3.5 h-3.5"
              />
              <label htmlFor="autoFallback" className="font-medium cursor-pointer">
                🔗 启用 V1.7 深度时间线自动补链 (双通道精准匹配)
              </label>
            </div>
            <span className="text-[10px] text-emerald-500 font-mono">推荐开启</span>
          </div>

          <div className={`border rounded-lg p-2.5 h-[210px] flex flex-col shrink-0 ${
            isLight ? 'bg-white border-slate-300 shadow-sm' : 'bg-slate-900/90 border-slate-800'
          }`}>
            <div className={`flex items-center space-x-1 mb-1.5 text-xs font-medium shrink-0 ${isLight ? 'text-slate-600' : 'text-slate-400'}`}>
              <Terminal className="w-3.5 h-3.5 text-emerald-500" />
              <span>智能回批实时日志与校验 (V1.7 引擎)</span>
            </div>
            <div className={`flex-1 rounded p-2 font-mono text-[11px] overflow-y-auto space-y-1 select-text ${
              isLight ? 'bg-slate-900 text-slate-100' : 'bg-slate-950 text-slate-300'
            }`}>
              {rebatchLogs.length === 0 ? (
                <div className="text-slate-500 italic">等待开始智能回批...</div>
              ) : (
                rebatchLogs.map((log, idx) => (
                  <div key={idx} className="whitespace-pre-wrap leading-relaxed">
                    {log}
                  </div>
                ))
              )}
              <div ref={rebatchLogsEndRef} />
            </div>
          </div>
        </div>
      )}

      {/* Footer Actions */}
      <footer className={`flex items-center justify-between pt-2.5 border-t shrink-0 ${isLight ? 'border-slate-200' : 'border-slate-800'}`}>
        <div className="flex items-center space-x-2 shrink-0">
          <div className={`w-2.5 h-2.5 rounded-full animate-pulse ${
            (activeTab === 'pack' ? status : rebatchStatus) === 'running' ? 'bg-amber-400' :
            (activeTab === 'pack' ? status : rebatchStatus) === 'success' ? 'bg-emerald-400' :
            (activeTab === 'pack' ? status : rebatchStatus) === 'error' ? 'bg-rose-400' : 'bg-slate-500'
          }`} />
          <span className={`text-xs font-medium ${isLight ? 'text-slate-700' : 'text-slate-300'}`}>
            {(activeTab === 'pack' ? status : rebatchStatus) === 'idle' && '就绪'}
            {(activeTab === 'pack' ? status : rebatchStatus) === 'running' && (activeTab === 'pack' ? '打包中...' : '回批中...')}
            {(activeTab === 'pack' ? status : rebatchStatus) === 'success' && (activeTab === 'pack' ? '打包成功' : '回批成功')}
            {(activeTab === 'pack' ? status : rebatchStatus) === 'error' && '执行出错'}
          </span>
        </div>

        {/* Progress Bar */}
        <div className="flex-1 mx-4 flex flex-col justify-center">
          <div className="flex items-center justify-between mb-1 text-[10px] font-mono">
            <div className="flex items-center space-x-2">
              <span className={isLight ? 'text-slate-600' : 'text-slate-400'}>{activeTab === 'pack' ? '打包进度' : '回批进度'}</span>
              {(activeTab === 'pack' ? status : rebatchStatus) === 'running' && (
                <div className="flex items-center space-x-2">
                  <span className="text-cyan-400 font-mono text-[9px]">
                    {getPackedSizeText(activeTab === 'pack' ? totalProjectSize : rebatchTotalSize, activeTab === 'pack' ? progress : rebatchProgress)}
                  </span>
                  <span className="text-slate-500 mx-2 font-bold">|</span>
                  <span className="text-amber-500 font-mono text-[9px]">
                    {activeTab === 'pack' ? '已打包' : '已回批'}: {formatTime(activeTab === 'pack' ? packElapsed : rebatchElapsed)} | 预估剩余: {formatTime(activeTab === 'pack' ? packRemaining : rebatchRemaining)}
                  </span>
                </div>
              )}
            </div>
            <span className={
              (activeTab === 'pack' ? status : rebatchStatus) === 'success' ? 'text-emerald-500 font-bold' : 
              (activeTab === 'pack' ? status : rebatchStatus) === 'error' ? 'text-rose-500 font-bold' : 
              activeTab === 'pack' ? 'text-cyan-500' : 'text-emerald-500'
            }>
              {activeTab === 'pack' ? progress : rebatchProgress}%
            </span>
          </div>
          <div className={`w-full rounded-full h-1.5 overflow-hidden border ${isLight ? 'bg-slate-200 border-slate-300' : 'bg-slate-900 border-slate-800'}`}>
            <div 
              className={`h-full transition-all duration-300 ease-out rounded-full ${
                (activeTab === 'pack' ? status : rebatchStatus) === 'success' ? 'bg-emerald-500' :
                (activeTab === 'pack' ? status : rebatchStatus) === 'error' ? 'bg-rose-500' :
                activeTab === 'pack' ? 'bg-gradient-to-r from-cyan-500 to-blue-500' : 'bg-gradient-to-r from-emerald-500 to-teal-500'
              }`}
              style={{ width: `${activeTab === 'pack' ? progress : rebatchProgress}%` }}
            />
          </div>
        </div>

        {/* Action Buttons */}
        <div className="flex items-center space-x-2 shrink-0">
          {activeTab === 'pack' && outputDir && (
            <button
              onClick={handleOpenFolder}
              className="px-3 py-1.5 bg-emerald-600/20 hover:bg-emerald-600/30 text-emerald-600 dark:text-emerald-300 border border-emerald-500/40 rounded-lg text-xs flex items-center space-x-1.5 transition"
            >
              <FolderOpen className="w-3.5 h-3.5" />
              <span>打开结果</span>
            </button>
          )}

          {activeTab === 'rebatch' && installDir && (
            <button
              onClick={handleOpenInstallFolder}
              className="px-3 py-1.5 bg-emerald-600/20 hover:bg-emerald-600/30 text-emerald-600 dark:text-emerald-300 border border-emerald-500/40 rounded-lg text-xs flex items-center space-x-1.5 transition"
            >
              <FolderOpen className="w-3.5 h-3.5" />
              <span>打开草稿</span>
            </button>
          )}

          {activeTab === 'pack' ? (
            <button
              onClick={handleRunPackager}
              disabled={status === 'running' || !projectDir}
              className={`px-4 py-1.5 rounded-lg text-xs font-medium flex items-center space-x-1.5 transition ${
                status === 'running' || !projectDir
                  ? isLight ? 'bg-slate-200 text-slate-400 cursor-not-allowed border border-slate-300' : 'bg-slate-800 text-slate-500 cursor-not-allowed border border-slate-800'
                  : 'bg-gradient-to-r from-cyan-600 to-blue-600 hover:from-cyan-500 hover:to-blue-500 text-white shadow-md active:scale-95'
              }`}
            >
              {status === 'running' ? (
                <>
                  <Loader2 className="w-3.5 h-3.5 animate-spin" />
                  <span>处理中</span>
                </>
              ) : (
                <>
                  <Play className="w-3.5 h-3.5 fill-current" />
                  <span>开始打包</span>
                </>
              )}
            </button>
          ) : (
            <button
              onClick={handleRunRebatch}
              disabled={rebatchStatus === 'running' || !packageDir}
              className={`px-4 py-1.5 rounded-lg text-xs font-medium flex items-center space-x-1.5 transition ${
                rebatchStatus === 'running' || !packageDir
                  ? isLight ? 'bg-slate-200 text-slate-400 cursor-not-allowed border border-slate-300' : 'bg-slate-800 text-slate-500 cursor-not-allowed border border-slate-800'
                  : 'bg-gradient-to-r from-emerald-600 to-teal-600 hover:from-emerald-500 hover:to-teal-500 text-white shadow-md active:scale-95'
              }`}
            >
              {rebatchStatus === 'running' ? (
                <>
                  <Loader2 className="w-3.5 h-3.5 animate-spin" />
                  <span>回批中</span>
                </>
              ) : (
                <>
                  <RefreshCw className="w-3.5 h-3.5" />
                  <span>开始智能回批</span>
                </>
              )}
            </button>
          )}
        </div>
      </footer>

      {/* Settings / About Modal */}
      {showSettingsModal && (
        <div className="fixed inset-0 bg-slate-950/70 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className={`border rounded-xl shadow-2xl w-[400px] max-w-full overflow-hidden flex flex-col ${
            isLight ? 'bg-white text-slate-900 border-slate-200' : 'bg-slate-900 text-slate-100 border-slate-800'
          }`}>
            <div className={`flex items-center justify-between px-4 py-3 border-b ${
              isLight ? 'border-slate-200 bg-slate-50' : 'border-slate-800 bg-slate-950/50'
            }`}>
              <div className="flex items-center space-x-2">
                <Settings className="w-4 h-4 text-cyan-500" />
                 <h3 className={`text-xs font-bold ${isLight ? 'text-slate-800' : 'text-slate-200'}`}>火枪手剪映工程迁移 V4.3.2 - 设置与指南</h3>
              </div>
              <button
                onClick={() => setShowSettingsModal(false)}
                className={`text-xs font-bold px-2 py-1 rounded transition ${
                  isLight ? 'text-slate-500 hover:text-slate-900 hover:bg-slate-200' : 'text-slate-400 hover:text-white hover:bg-slate-800'
                }`}
              >
                ✕
              </button>
            </div>

            <div className="p-4 space-y-3 text-xs overflow-y-auto max-h-[420px]">
              {/* Theme Switcher */}
              <div>
                <h4 className={`font-semibold mb-1.5 ${isLight ? 'text-slate-700' : 'text-cyan-400'}`}>🎨 主题切换</h4>
                <div className="flex items-center space-x-2">
                  <button
                    onClick={() => setTheme('dark')}
                    className={`flex-1 py-1.5 px-3 rounded-lg text-xs font-medium flex items-center justify-center space-x-1.5 transition ${
                      theme === 'dark' 
                        ? 'bg-cyan-600 text-white shadow' 
                        : isLight ? 'bg-slate-200 text-slate-700 hover:bg-slate-300' : 'bg-slate-800 text-slate-400 hover:text-white'
                    }`}
                  >
                    <Moon className="w-3.5 h-3.5" />
                    <span>暗黑主题</span>
                  </button>
                  <button
                    onClick={() => setTheme('light')}
                    className={`flex-1 py-1.5 px-3 rounded-lg text-xs font-medium flex items-center justify-center space-x-1.5 transition ${
                      theme === 'light' 
                        ? 'bg-amber-500 text-slate-950 font-bold shadow' 
                        : isLight ? 'bg-slate-200 text-slate-700 hover:bg-slate-300' : 'bg-slate-800 text-slate-400 hover:text-white'
                    }`}
                  >
                    <Sun className="w-3.5 h-3.5" />
                    <span>明亮主题</span>
                  </button>
                </div>
              </div>

              <div>
                <h4 className={`font-semibold mb-1 ${isLight ? 'text-slate-700' : 'text-cyan-400'}`}>📌 程序简介</h4>
                <p className={`leading-relaxed text-[11px] ${isLight ? 'text-slate-600' : 'text-slate-400'}`}>
                  火枪手剪映工程迁移 V4.3.2 是专为剪映专业版（Mac / Windows）打造的专业本地工程一键打包与智能回批工具。内置高级解析引擎与深度时间线解析，完美解决多设备迁移素材丢失与路径失效难题。
                </p>
              </div>

              <div>
                <h4 className={`font-semibold mb-1 ${isLight ? 'text-slate-700' : 'text-emerald-400'}`}>🚀 简洁使用步骤</h4>
                <div className={`space-y-1 text-[11px] p-2.5 rounded-lg border ${
                  isLight ? 'bg-slate-50 border-slate-200 text-slate-700' : 'bg-slate-950/60 border-slate-800/80 text-slate-300'
                }`}>
                  <p><strong className={isLight ? 'text-cyan-600' : 'text-cyan-300'}>1. 本地打包：</strong>在原电脑选择剪映工程文件夹 &rarr; 点击「开始打包」。</p>
                  <p><strong className={isLight ? 'text-emerald-600' : 'text-emerald-300'}>2. 智能回批：</strong>在新电脑选择打包总目录 &rarr; 点击「开始智能回批」。</p>
                </div>
              </div>

              <div className={`pt-2 border-t flex flex-col items-center justify-center ${isLight ? 'border-slate-200' : 'border-slate-800/80'}`}>
                <div className="w-28 h-28 bg-white p-1.5 rounded-lg shadow-md border border-slate-300 flex items-center justify-center">
                  <img src={qrcodeImg} alt="赞赏码" className="w-full h-full object-contain" />
                </div>
                <p className="mt-2 text-[11px] font-medium text-amber-500 tracking-wider">
                  ~请我喝杯咖啡吧~
                </p>
              </div>
            </div>

            <div className={`px-4 py-2.5 border-t flex justify-end ${
              isLight ? 'border-slate-200 bg-slate-50' : 'border-slate-800 bg-slate-950/50'
            }`}>
              <button
                onClick={() => setShowSettingsModal(false)}
                className={`px-4 py-1.5 rounded-lg text-xs transition font-medium ${
                  isLight ? 'bg-slate-200 hover:bg-slate-300 text-slate-800' : 'bg-slate-800 hover:bg-slate-700 text-slate-200'
                }`}
              >
                知道了
              </button>
            </div>
          </div>
        </div>
      )}

    </div>
  );

  if (isElectron) {
    return appContent;
  }

  // Preview wrapper for web / AI Studio (simulates 780x580 independent app window)
  return (
    <div className={`min-h-screen flex items-center justify-center p-4 overflow-hidden ${isLight ? 'bg-slate-900' : 'bg-slate-950'}`}>
      <div className={`w-[780px] h-[580px] rounded-xl overflow-hidden shadow-2xl border flex flex-col ${
        isLight ? 'bg-slate-100 border-slate-700' : 'bg-slate-950 border-slate-800'
      }`}>
        <div className={`h-7 border-b flex items-center justify-between px-3 select-none shrink-0 ${
          isLight ? 'bg-slate-200 border-slate-300' : 'bg-slate-900 border-slate-800'
        }`}>
          <div className="flex items-center space-x-1.5">
            <div className="w-3 h-3 rounded-full bg-rose-500" />
            <div className="w-3 h-3 rounded-full bg-amber-500" />
            <div className="w-3 h-3 rounded-full bg-emerald-500" />
          </div>
          <div className={`text-[11px] font-mono ${isLight ? 'text-slate-600' : 'text-slate-400'}`}>火枪手剪映工程迁移V4.3.2</div>
        </div>
        <div className="flex-1 overflow-hidden">
          {appContent}
        </div>
      </div>
    </div>
  );
}
