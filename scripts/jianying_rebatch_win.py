#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
剪映 Windows 工程智能回批引擎 V1.2 (Windows 适配版)
自动扫描 V4.0 打包目录，建立绝对路径与相对素材映射，
将工程恢复至新 Windows 电脑的剪映默认草稿目录中。
"""

import sys
import os
import json
import shutil
from pathlib import Path

def log(msg):
    print(msg)
    sys.stdout.flush()

def main():
    if len(sys.argv) < 2:
        log("错误：未指定打包总目录")
        sys.exit(1)

    package_dir = Path(sys.argv[1]).resolve()
    manifest_path = package_dir / "V4.0_打包诊断.txt"

    if not manifest_path.is_file():
        log("错误：所选目录不是有效的 V4.0 打包目录（缺少 V4.0_打包诊断.txt）")
        sys.exit(2)

    if not (package_dir / "画面素材").is_dir() or not (package_dir / "音频").is_dir():
        log("错误：V4.0 打包目录结构不完整（缺少 画面素材 / 音频 文件夹）")
        sys.exit(3)

    log("============================================================")
    log("剪映 Windows 工程智能回批 V1.2")
    log("============================================================")
    log(f"打包目录: {package_dir}")

    # Find project subfolder inside package dir
    sub_dirs = [p for p in package_dir.iterdir() if p.is_dir() and p.name not in ('画面素材', '音频') and not p.name.startswith('.')]
    if not sub_dirs:
        log("错误：在打包目录中未找到工程子文件夹")
        sys.exit(4)

    src_proj_dir = sub_dirs[0]
    log(f"识别到工程文件夹: {src_proj_dir.name}")

    # Determine default Jianying Windows Drafts directory
    # Typically C:\Users\<user>\AppData\Local\JianyingPro\User Data\Projects\com.lveditor.draft
    user_home = Path.home()
    default_drafts = user_home / "AppData" / "Local" / "JianyingPro" / "User Data" / "Projects" / "com.lveditor.draft"
    if not default_drafts.exists():
        # Fallback to general documents or user profile
        default_drafts = user_home / "JianyingPro" / "User Data" / "Projects" / "com.lveditor.draft"
    
    default_drafts.mkdir(parents=True, exist_ok=True)
    dest_proj_dir = default_drafts / src_proj_dir.name

    log(f"目标安装草稿目录: {dest_proj_dir}")

    # Copy project folder to drafts
    if dest_proj_dir.exists():
        shutil.rmtree(dest_proj_dir)
    shutil.copytree(src_proj_dir, dest_proj_dir)

    # Remap relative paths in json files inside dest_proj_dir to absolute paths pointing to package_dir
    json_files = list(dest_proj_dir.glob("**/*.json"))
    remap_count = 0

    for jf in json_files:
        try:
            content = jf.read_text(encoding='utf-8', errors='ignore')
            data = json.loads(content)
            modified = False

            def fix_obj(obj):
                nonlocal modified, remap_count
                if isinstance(obj, dict):
                    for k, v in obj.items():
                        if k in ('path', 'material_url', 'file_path', 'import_file_path') and isinstance(v, str) and v:
                            clean_v = v.replace('file:///', '').replace('file://', '')
                            # Check if it's relative path inside package
                            possible_file = package_dir / clean_v
                            if possible_file.is_file():
                                abs_path = str(possible_file.resolve()).replace('\\', '/')
                                if v.startswith('file://'):
                                    obj[k] = f"file:///{abs_path}"
                                else:
                                    obj[k] = abs_path
                                modified = True
                                remap_count += 1
                        else:
                            fix_obj(v)
                elif isinstance(obj, list):
                    for item in obj:
                        fix_obj(item)

            fix_obj(data)
            if modified:
                jf.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
        except Exception as e:
            pass

    log(f"路径回批重映射成功: {remap_count} 处素材路径已更新为新电脑绝对路径")
    log(f"OUTPUT_INSTALL_DIR={dest_proj_dir}")
    log("============================================================")
    log("回批完成！")
    log("============================================================")

if __name__ == '__main__':
    main()
