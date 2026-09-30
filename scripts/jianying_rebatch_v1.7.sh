#!/bin/bash
set -u

# ============================================================
# 剪映 Mac 工程智能回批 V1.7（基于 V1.2 稳定核心）
#
# 用途：
#   将 V4.0 打包目录带到新 Mac 后：
#   1. 选择整个 V4.0 打包目录；
#   2. 自动识别“工程目录 / 画面素材 / 音频 / V4.0_打包诊断.txt”；
#   3. 根据 V4.0 诊断文件建立“原始绝对路径 -> 新设备素材路径”映射；
#   4. 扫描工程内所有 JSON / 加密工程文件；
#   5. 普通 JSON 直接修改；
#   6. 加密 JSON 通过剪映原生 EncryptUtils 解密 -> 替换路径 -> 回加密；
#   7. 不修改打包目录中的原工程；
#   8. 生成一个独立的“回批临时工程”；
#   9. 通过校验后，将该工程目录安装到剪映默认草稿目录；
# ============================================================

PYTHON="$(command -v python3 2>/dev/null || true)"
CLANG="$(command -v clang++ 2>/dev/null || true)"

if [ -z "$PYTHON" ]; then
  echo "错误：找不到 python3。"
  read -r -p "按回车退出..." _
  exit 1
fi

PACKAGE_DIR="${1:-}"

if [ -z "$PACKAGE_DIR" ]; then
  PACKAGE_DIR="$(osascript <<'APPLESCRIPT'
try
  set f to choose folder with prompt "选择【剪映 V4.0 打包工程总目录】"
  POSIX path of f
on error
  return ""
end try
APPLESCRIPT
)"
fi

[ -n "$PACKAGE_DIR" ] || exit 0
PACKAGE_DIR="${PACKAGE_DIR%/}"

MANIFEST=""
for candidate in \
  "$PACKAGE_DIR/V4.3.2_打包诊断.txt" \
  "$PACKAGE_DIR/V4.3_打包诊断.txt" \
  "$PACKAGE_DIR/V4.0_打包诊断.txt"; do
  if [ -f "$candidate" ]; then
    MANIFEST="$candidate"
    break
  fi
done
if [ -z "$MANIFEST" ]; then
  echo ""
  echo "错误：所选目录不是有效的剪映打包目录。"
  read -r -p "按回车退出..." _
  exit 2
fi

if [ ! -d "$PACKAGE_DIR/画面素材" ] || [ ! -d "$PACKAGE_DIR/音频" ]; then
  echo ""
  echo "错误：V4.0 打包目录结构不完整。"
  read -r -p "按回车退出..." _
  exit 3
fi

PROJECT_DIR="$("$PYTHON" - "$MANIFEST" "$PACKAGE_DIR" <<'PY'
import sys,re
from pathlib import Path

manifest=Path(sys.argv[1])
package=Path(sys.argv[2])
text=manifest.read_text(encoding='utf-8',errors='replace')

m=re.findall(r'^工程目录：(.+)$',text,re.M)
old_path=m[-1].strip() if m else ''
expected_name=Path(old_path.rstrip('/')).name if old_path else ''

if expected_name:
    candidate=package/expected_name
    if candidate.is_dir() and candidate.name not in {'画面素材','音频'}:
        print(str(candidate))
        raise SystemExit(0)

excluded={'画面素材','音频'}
candidates=[
    p for p in package.iterdir()
    if p.is_dir() and p.name not in excluded and not p.name.startswith('.')
]

def looks_like_project(p):
    names=set()
    try:
        for q in p.iterdir(): names.add(q.name)
    except OSError: return False
    markers={'draft_info.json','draft_meta_info.json','root_meta_info.json','draft_content.json'}
    if names & markers: return True
    try:
        return any(q.is_file() and q.suffix.lower() in {'.json','.db','.sqlite','.sqlite3'} for q in p.iterdir())
    except OSError: return False

likely=[p for p in candidates if looks_like_project(p)]
if len(likely)==1:
    print(str(likely[0]))
    raise SystemExit(0)
if len(candidates)==1:
    print(str(candidates[0]))
    raise SystemExit(0)
print('')
PY
)"

if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
  PROJECT_DIR="$(osascript <<APPLESCRIPT
try
  set baseFolder to POSIX file "$PACKAGE_DIR" as alias
  set f to choose folder with prompt "自动识别失败，请选择 V4.0 打包目录内的【工程文件夹】" default location baseFolder
  POSIX path of f
on error
  return ""
end try
APPLESCRIPT
)"
  PROJECT_DIR="${PROJECT_DIR%/}"
fi

if [ -z "$PROJECT_DIR" ] || [ ! -d "$PROJECT_DIR" ]; then
  echo "错误：无法确定 V4.0 打包目录内的工程目录。"
  read -r -p "按回车退出..." _
  exit 4
fi

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/jianying-rebatch-v1.XXXXXX")"
cleanup() { rm -rf "$TMP_ROOT"; }
trap cleanup EXIT INT TERM

APP_CANDIDATES=(
  "/Applications/剪映专业版.app"
  "/Applications/JianyingPro.app"
  "$HOME/Applications/剪映专业版.app"
  "$HOME/Applications/JianyingPro.app"
)

find_dylib() {
  local app="$1"
  [ -d "$app" ] || return 1
  for p in \
    "$app/Contents/Frameworks/libvideoeditor.dylib" \
    "$app/Contents/Frameworks/videoeditor/libvideoeditor.dylib" \
    "$app/Contents/Resources/libvideoeditor.dylib" \
    "$app/Contents/MacOS/libvideoeditor.dylib"; do
    [ -f "$p" ] && { echo "$p"; return 0; }
  done
  find "$app/Contents" -type f \( -name 'libvideoeditor.dylib' -o -name 'videoeditor.dylib' \) -print -quit 2>/dev/null
}

JY_APP=""
LIB=""
for app in "${APP_CANDIDATES[@]}"; do
  if [ -d "$app" ]; then
    x="$(find_dylib "$app" || true)"
    if [ -n "$x" ]; then JY_APP="$app"; LIB="$x"; break; fi
  fi
done

if [ -z "$LIB" ]; then
  LIB="$(find /Applications "$HOME/Applications" -type f \( -name 'libvideoeditor.dylib' -o -name 'videoeditor.dylib' \) -print -quit 2>/dev/null || true)"
  [ -n "$LIB" ] && JY_APP="$(dirname "$(dirname "$(dirname "$LIB")")")"
fi

if [ -z "$LIB" ]; then
  echo "没有找到剪映的 libvideoeditor.dylib。"
  read -r -p "按回车退出..." _
  exit 5
fi

if [ -z "$CLANG" ]; then
  echo "没有找到 clang++。"
  read -r -p "按回车退出..." _
  exit 6
fi

FRAMEWORKS_DIR="$(dirname "$LIB")"
LIBAGFX="$(find "$FRAMEWORKS_DIR" "$JY_APP/Contents" -type f -name "libAGFX.dylib" -print -quit 2>/dev/null || true)"
if [ -z "$LIBAGFX" ]; then
  echo "未找到 libAGFX.dylib。"
  read -r -p "按回车退出..." _
  exit 7
fi

DYLD_DIRS="$FRAMEWORKS_DIR"
while IFS= read -r d; do
  [ -n "$d" ] && DYLD_DIRS="$DYLD_DIRS:$d"
done < <(find "$JY_APP/Contents" -type f -name "*.dylib" -print 2>/dev/null | xargs -n1 dirname 2>/dev/null | sort -u)

export DYLD_LIBRARY_PATH="$DYLD_DIRS${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
export DYLD_FALLBACK_LIBRARY_PATH="$FRAMEWORKS_DIR${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
export DYLD_FRAMEWORK_PATH="$FRAMEWORKS_DIR${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"

cat > "$TMP_ROOT/EncryptUtil.h" <<'CPP'
#ifndef EncryptUtil_h
#define EncryptUtil_h
#include <string>
#include <cstring>
#include <utility>

struct MsvcString {
    union { char small[16]; char *ptr; } data{};
    unsigned long long size = 0;
    unsigned long long capacity = 15;
};
struct StrArg {
    std::string storage;
    MsvcString s;
    explicit StrArg(std::string v) : storage(std::move(v)) {
        s.size = storage.size();
        if (storage.size() < 16) {
            memset(s.data.small, 0, sizeof(s.data.small));
            memcpy(s.data.small, storage.data(), storage.size());
        } else {
            storage.push_back('\0'); storage.pop_back();
            s.capacity = storage.size(); s.data.ptr = storage.data();
        }
    }
};
namespace lvve {
class EncryptUtils {
public:
    bool isEnable();
    void enable(bool);
    std::string encrypt(const std::string& inStr);
    std::string decrypt(const std::string& s1, const std::string& s2);
    std::string decrypt(const std::string& s1, const std::string& s2, bool& flag);
};
}
#endif
CPP

cat > "$TMP_ROOT/jycrypto.cpp" <<'CPP'
#include <dlfcn.h>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include "EncryptUtil.h"

static std::string readall(const std::string& p){
  std::ifstream f(p, std::ios::binary);
  if(!f) throw std::runtime_error("cannot open input: "+p);
  std::ostringstream s; s << f.rdbuf(); return s.str();
}
static void writeall(const std::string& p,const std::string& s){
  std::ofstream f(p,std::ios::binary|std::ios::trunc);
  if(!f) throw std::runtime_error("cannot open output: "+p);
  f.write(s.data(), (std::streamsize)s.size());
}

int main(int argc,char**argv){
  if(argc<4 || argc>5) return 64;
  try{
    void* h=dlopen(argv[1], RTLD_NOW|RTLD_GLOBAL);
    if(!h) throw std::runtime_error("dlopen failed");
    std::string in=readall(argv[3]);
    lvve::EncryptUtils c;
    c.enable(true);
    if(std::string(argv[2])=="decrypt"){
      bool valid=false;
      std::string out=c.decrypt(in,"{}",valid);
      if(!valid || out.empty()) throw std::runtime_error("decrypt failed");
      writeall(argv[4],out);
      std::cout<<"OK "<<out.size()<<std::endl;
    }else if(std::string(argv[2])=="encrypt"){
      std::string out=c.encrypt(in);
      if(out.empty()) throw std::runtime_error("encrypt failed");
      writeall(argv[4],out);
      std::cout<<"OK "<<out.size()<<std::endl;
    }
    dlclose(h);
    return 0;
  }catch(const std::exception&e){
    std::cerr<<"ERROR: "<<e.what()<<"\n";
    return 1;
  }
}
CPP

"$CLANG" -std=c++17 -O2 -Wl,-undefined,dynamic_lookup "$TMP_ROOT/jycrypto.cpp" -o "$TMP_ROOT/jycrypto" -ldl 2>/dev/null || exit 8

DEFAULT_ROOTS=(
  "$HOME/Movies/JianyingPro/User Data/Projects/com.lveditor.draft"
  "$HOME/Movies/剪映专业版/User Data/Projects/com.lveditor.draft"
  "$HOME/Movies/CapCut/User Data/Projects/com.lveditor.draft"
)

TARGET_ROOT=""
for d in "${DEFAULT_ROOTS[@]}"; do
  [ -d "$d" ] && { TARGET_ROOT="$d"; break; }
done

[ -z "$TARGET_ROOT" ] && TARGET_ROOT="$(find "$HOME/Movies" -type d -path '*/User Data/Projects/com.lveditor.draft' -print -quit 2>/dev/null || true)"

if [ -z "$TARGET_ROOT" ] || [ ! -d "$TARGET_ROOT" ]; then
  TARGET_ROOT="$(osascript <<'APPLESCRIPT'
try
  set f to choose folder with prompt "请选择剪映默认草稿目录【com.lveditor.draft】"
  POSIX path of f
on error
  return ""
end try
APPLESCRIPT
)"
  TARGET_ROOT="${TARGET_ROOT%/}"
fi

[ -n "$TARGET_ROOT" ] && [ -d "$TARGET_ROOT" ] || exit 9

MAP_FILE="$TMP_ROOT/path_map.tsv"
"$PYTHON" - "$MANIFEST" "$MAP_FILE" "$PACKAGE_DIR" <<'PY'
import sys,re
from pathlib import Path

manifest=Path(sys.argv[1])
out=Path(sys.argv[2])
current_package=Path(sys.argv[3]).resolve()
lines=manifest.read_text(encoding='utf-8',errors='replace').splitlines()
pairs=[]
current_src=None

def relocate_packaged_path(old_dst):
    s=old_dst.strip()
    if not s: return ''
    if s.startswith('file://localhost'): s=s[16:]
    elif s.startswith('file://'): s=s[7:]
    s=s.replace('\\','/')
    for marker in ('/画面素材/','/音频/'):
        pos=s.find(marker)
        if pos >= 0:
            rel=s[pos+1:]
            return str((current_package/Path(rel)).resolve())
    if not s.startswith('/'):
        return str((current_package/s).resolve())
    return s

for line in lines:
    m=re.match(r'^\[[^\]]+\].*\t(.+)$',line)
    if m:
        current_src=m.group(1).strip()
        continue
    if line.startswith('包内：') and current_src:
        dst=relocate_packaged_path(line[3:])
        if dst: pairs.append((current_src,dst))
        current_src=None

seen=set()
with out.open('w',encoding='utf-8') as f:
    for src,dst in pairs:
        key=(src,dst)
        if key in seen: continue
        seen.add(key)
        f.write(src+'\t'+dst+'\n')
print(len(seen))
PY

"$PYTHON" - "$PROJECT_DIR" "$PACKAGE_DIR" "$TARGET_ROOT" "$MAP_FILE" \
  "$TMP_ROOT/jycrypto" "$LIB" "$TMP_ROOT" <<'PY'
import sys, os, json, re, shutil, subprocess, time, urllib.parse
from pathlib import Path

project=Path(sys.argv[1]).resolve()
package=Path(sys.argv[2]).resolve()
target_root=Path(sys.argv[3]).resolve()
map_file=Path(sys.argv[4])
crypto=Path(sys.argv[5])
lib=Path(sys.argv[6])
tmp=Path(sys.argv[7])

MEDIA_EXT={
    '.mp4','.mov','.mxf','.m4v','.avi','.mkv','.webm',
    '.mp3','.wav','.aac','.m4a','.flac','.ogg','.aiff','.aif',
    '.jpg','.jpeg','.png','.webp','.heic','.tif','.tiff','.gif',
    '.bmp','.dng','.arw','.cr2','.cr3','.nef','.raf','.rw2',
    '.orf','.sr2','.braw','.r3d','.avif',
}

def valid_json_bytes(data):
    try:
        s=data.decode('utf-8-sig',errors='strict').strip()
        if not s: return None
        o=json.loads(s)
        if isinstance(o,(dict,list)): return o
    except Exception: pass
    return None

def valid_json_file(p):
    try: return valid_json_bytes(p.read_bytes())
    except Exception: return None

mapping={}
for raw in map_file.read_text(encoding='utf-8',errors='replace').splitlines():
    if '\t' not in raw: continue
    src,dst=raw.split('\t',1)
    src=src.strip(); dst=dst.strip()
    if src and dst: mapping[src]=dst

replace_map={}
for old,new in mapping.items():
    old=str(Path(old)); new=str(Path(new))
    variants={
        old:new,
        'file://'+old:'file://'+new,
        'file://localhost'+old:'file://localhost'+new,
        urllib.parse.quote(old,safe='/:-_.~'):urllib.parse.quote(new,safe='/:-_.~'),
    }
    replace_map.update(variants)
replace_items=sorted(replace_map.items(), key=lambda kv:len(kv[0]), reverse=True)

video_root=package/'画面素材'
audio_root=package/'音频'
package_by_name={}
package_assets=[]

for root in (video_root,audio_root):
    if not root.is_dir(): continue
    for p in root.rglob('*'):
        if not p.is_file() or p.suffix.lower() not in MEDIA_EXT: continue
        try:
            rp=p.resolve()
            rel=str(rp.relative_to(package.resolve())).replace('\\','/')
        except Exception: continue
        package_assets.append((rp,rel))
        package_by_name.setdefault(rp.name.lower(),[]).append(rp)

def tail4(v):
    z=v.strip().strip('"').strip("'")
    if z.startswith('file://localhost'): z=z[16:]
    elif z.startswith('file://'): z=z[7:]
    z=urllib.parse.unquote(z).replace('\\','/')
    parts=[x for x in z.split('/') if x]
    return '/'.join(x.lower() for x in parts[-4:])

package_tail4={}
for p,rel in package_assets:
    package_tail4.setdefault(tail4(rel),[]).append(p)

MEDIA_PATH_RE=re.compile(
    r'(?:(?:file://(?:localhost)?/)|/Users/|/Volumes/|/private/|[A-Za-z]:[\\/])'
    r'[^"\'\r\n\\]+?'
    r'\.(?:mp4|mov|mxf|m4v|avi|mkv|webm|mp3|wav|aac|m4a|flac|ogg|aiff|aif|jpg|jpeg|png|webp|heic|tif|tiff|gif|bmp|dng|arw|cr2|cr3|nef|raf|rw2|orf|sr2|braw|r3d|avif)'
    r'(?:\b|$)',
    re.I
)

fallback_links={}
unpackaged_paths=[]
changed_files=0

def resolve_fallback(old_path):
    z=old_path.strip().strip('"').strip("'")
    if z.startswith('file://localhost'): z=z[16:]
    elif z.startswith('file://'): z=z[7:]
    z=urllib.parse.unquote(z).replace('\\','/')
    if not z: return None
    key=tail4(z)
    cands=package_tail4.get(key,[])
    if len(cands)==1: return cands[0]
    name=Path(z).name.lower()
    cands=package_by_name.get(name,[])
    if len(cands)==1: return cands[0]
    unpackaged_paths.append(z)
    return None

def replace_string(s):
    if not isinstance(s,str) or not s: return s
    z=s
    for old,new in replace_items:
        if old in z: z=z.replace(old,new)
    def repl(m):
        raw=m.group(0)
        target=resolve_fallback(raw)
        if target:
            fallback_links[raw]=str(target)
            return str(target)
        return raw
    return MEDIA_PATH_RE.sub(repl,z)

def transform(x):
    if isinstance(x,dict): return {k:transform(v) for k,v in x.items()}
    if isinstance(x,list): return [transform(v) for v in x]
    if isinstance(x,str): return replace_string(x)
    return x

def decrypt(src,out):
    try:
        r=subprocess.run([str(crypto),str(lib),'decrypt',str(src),str(out)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=5.0)
        if r.returncode!=0 or not out.exists(): return None
        return valid_json_file(out)
    except Exception: return None

def encrypt(src,out):
    try:
        r=subprocess.run([str(crypto),str(lib),'encrypt',str(src),str(out)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=8.0)
        return r.returncode==0 and out.exists() and out.stat().st_size>0
    except Exception: return False

install_dir=target_root/project.name
staging=tmp/'staging'/project.name
staging.mkdir(parents=True,exist_ok=True)

for src in project.rglob('*'):
    rel=src.relative_to(project)
    dst=staging/rel
    if src.is_dir(): dst.mkdir(parents=True,exist_ok=True)
    else:
        dst.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(src,dst)

files=[p for p in staging.rglob('*') if p.is_file() and p.name!='.DS_Store' and p.suffix.lower() not in MEDIA_EXT]

for idx,p in enumerate(files,1):
    obj=valid_json_file(p)
    if obj is not None:
        new_obj=transform(obj)
        if new_obj!=obj:
            tmp_json=tmp/'plain_out.json'
            tmp_json.write_text(json.dumps(new_obj,ensure_ascii=False,separators=(',',':')), encoding='utf-8')
            os.replace(tmp_json,p)
            changed_files+=1
        continue

    dec=tmp/f"dec_{idx}.json"
    obj=decrypt(p,dec)
    if obj is None: continue
    new_obj=transform(obj)
    if new_obj==obj: continue
    mod=tmp/f"mod_{idx}.json"
    mod.write_text(json.dumps(new_obj,ensure_ascii=False,separators=(',',':')), encoding='utf-8')
    enc=tmp/f"enc_{idx}"
    if encrypt(mod,enc):
        os.replace(enc,p)
        changed_files+=1

if changed_files==0:
    raise RuntimeError("没有任何工程文件发生路径替换。")

if install_dir.exists():
    if install_dir.is_dir(): shutil.rmtree(install_dir)
    else: install_dir.unlink()

shutil.copy2(staging,install_dir) if not staging.is_dir() else shutil.copytree(staging,install_dir)
print(f"OUTPUT_INSTALL_DIR={install_dir}", flush=True)
PY

PY_STATUS=$?
[ "$PY_STATUS" -eq 0 ] || exit "$PY_STATUS"

OPEN_TARGET="$(sed -n 's/^OUTPUT_INSTALL_DIR=//p' "$TMP_ROOT/python_output.log" | tail -n 1)"
[ -n "$OPEN_TARGET" ] || OPEN_TARGET="$TARGET_ROOT"
open "$OPEN_TARGET" >/dev/null 2>&1 || true
