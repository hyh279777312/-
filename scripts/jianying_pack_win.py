#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
剪映 Windows 本地工程打包引擎 V4.0 (Windows 适配版)
无需解密库（Windows 下剪映工程为标准 JSON），深度解析时间线，
智能提取画面素材与音频，生成便携打包目录与诊断日志。
"""

import sys
import os
import json
import shutil
import re
from pathlib import Path

def log(msg):
    print(msg)
    sys.stdout.flush()

def main():
    if len(sys.argv) < 2:
        log("错误：未指定工程目录")
        sys.exit(1)

    project_dir = Path(sys.argv[1]).resolve()
    custom_output = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None

    if not project_dir.is_dir():
        log(f"错误：工程目录不存在: {project_dir}")
        sys.exit(1)

    # Output directory
    proj_name = project_dir.name
    if custom_output:
        out_root = Path(custom_output).resolve() / f"{proj_name}_打包版"
    else:
        out_root = project_dir.parent / f"{proj_name}_打包版"

    out_root.mkdir(parents=True, exist_ok=True)
    video_dir = out_root / "画面素材"
    audio_dir = out_root / "音频"
    video_dir.mkdir(exist_ok=True)
    audio_dir.mkdir(exist_ok=True)

    # Copy project structure
    target_proj_dir = out_root / proj_name
    if target_proj_dir.exists():
        shutil.rmtree(target_proj_dir)
    shutil.copytree(project_dir, target_proj_dir)

    log(f"============================================================")
    log(f"剪映 Windows 本地工程打包 V4.0")
    log(f"============================================================")
    log(f"工程目录: {project_dir}")
    log(f"打包输出: {out_root}")
    log("")

    # Find JSON files in project
    json_files = list(target_proj_dir.glob("**/*.json"))
    referenced_files = set()
    path_mapping = {}

    for jf in json_files:
        try:
            content = jf.read_text(encoding='utf-8', errors='ignore')
            data = json.loads(content)
        except Exception:
            continue

        def scan_obj(obj):
            if isinstance(obj, dict):
                for k, v in obj.items():
                    if k in ('path', 'material_url', 'file_path', 'import_file_path') and isinstance(v, str) and v:
                        if os.path.isabs(v) or v.startswith('file://'):
                            clean_p = v.replace('file://', '')
                            if os.path.exists(clean_p):
                                referenced_files.add(clean_p)
                    else:
                        scan_obj(v)
            elif isinstance(obj, list):
                for item in obj:
                    scan_obj(item)

        scan_obj(data)

    log(f"共发现引用外部素材文件: {len(referenced_files)} 个")

    # Copy files and build mapping
    copied_count = 0
    for src_path_str in referenced_files:
        src_p = Path(src_path_str)
        if not src_p.is_file():
            continue
        ext = src_p.suffix.lower()
        is_audio = ext in ('.mp3', '.wav', '.m4a', '.aac', '.flac', '.ogg', '.wma')
        dest_folder = audio_dir if is_audio else video_dir
        dest_p = dest_folder / src_p.name

        # Handle name collision
        if dest_p.exists() and dest_p.resolve() != src_p.resolve():
            stem = src_p.stem
            dest_p = dest_folder / f"{stem}_{abs(hash(src_path_str)) % 10000}{ext}"

        try:
            shutil.copy2(src_p, dest_p)
            rel_dest = os.path.relpath(dest_p, out_root)
            path_mapping[src_path_str] = rel_dest
            copied_count += 1
        except Exception as e:
            log(f"警告：复制素材失败 {src_p}: {e}")

    log(f"成功复制素材: {copied_count} 个")

    # Rewrite JSON paths to relative/portable
    for jf in json_files:
        try:
            content = jf.read_text(encoding='utf-8', errors='ignore')
            data = json.loads(content)
            modified = False

            def rewrite_obj(obj):
                nonlocal modified
                if isinstance(obj, dict):
                    for k, v in obj.items():
                        if k in ('path', 'material_url', 'file_path', 'import_file_path') and isinstance(v, str) and v:
                            clean_p = v.replace('file://', '')
                            if clean_p in path_mapping:
                                new_val = path_mapping[clean_p].replace('\\', '/')
                                if v.startswith('file://'):
                                    obj[k] = f"file:///{new_val}"
                                else:
                                    obj[k] = new_val
                                modified = True
                        else:
                            rewrite_obj(v)
                elif isinstance(obj, list):
                    for item in obj:
                        rewrite_obj(item)

            rewrite_obj(data)
            if modified:
                jf.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
        except Exception as e:
            pass

    # Generate Manifest
    manifest_path = out_root / "V4.0_打包诊断.txt"
    manifest_content = f"""============================================================
剪映 Windows 工程打包诊断日志 V4.0
============================================================
工程目录：{project_dir}
打包时间：{os.popen('date /t').read().strip()} {os.popen('time /t').read().strip()}
原始素材数：{len(referenced_files)}
成功复制数：{copied_count}
输出目录：{out_root}
============================================================
原工程没有被修改。
============================================================
"""
    manifest_path.write_text(manifest_content, encoding='utf-8')

    log(f"OUTPUT_DIR={out_root}")
    log("============================================================")
    log("打包成功！")
    log("============================================================")

if __name__ == '__main__':
    main()
