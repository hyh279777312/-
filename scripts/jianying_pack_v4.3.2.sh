#!/bin/bash
set -u

# 剪映 Mac 本地工程打包 V4.3.2
# 目标：调用本机已安装的剪映原生 EncryptUtils 解密主草稿，解析真实时间线，
#      只复制时间线上实际引用的本地素材。
# 不修改原工程；所有解密文件放在临时目录，结束后自动删除。

PYTHON="$(command -v python3 2>/dev/null || true)"
CLANG="$(command -v clang++ 2>/dev/null || true)"

if [ -z "$PYTHON" ]; then
  echo "错误：找不到 python3。"
  read -r -p "按回车退出..." _
  exit 1
fi

PROJECT_DIR="${PROJECT_DIR:-${1:-}}"
CUSTOM_OUTPUT_DIR="${CUSTOM_OUTPUT_DIR:-${2:-}}"

if [ -z "$PROJECT_DIR" ] || [ "$PROJECT_DIR" = "undefined" ]; then
  PROJECT_DIR="$(osascript <<'APPLESCRIPT'
try
  set f to choose folder with prompt "选择【剪映 Mac 工程文件夹】"
  POSIX path of f
on error
  return ""
end try
APPLESCRIPT
)"
fi

[ -n "$PROJECT_DIR" ] || exit 0
PROJECT_DIR="${PROJECT_DIR%/}"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/jianying-v3.XXXXXX")"
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
  # 最后从 /Applications 和用户 Applications 搜索，避免依赖固定安装路径。
  LIB="$(find /Applications "$HOME/Applications" -type f \( -name 'libvideoeditor.dylib' -o -name 'videoeditor.dylib' \) -print -quit 2>/dev/null || true)"
  [ -n "$LIB" ] && JY_APP="$(dirname "$(dirname "$(dirname "$LIB")")")"
fi

if [ -z "$LIB" ]; then
  echo "没有找到剪映的 libvideoeditor.dylib。"
  echo ""
  echo "请确认本机已安装剪映 Mac 专业版，然后重新运行。"
  read -r -p "按回车退出..." _
  exit 2
fi

if [ -z "$CLANG" ]; then
  echo "没有找到 clang++。"
  echo "V3 不需要完整 Xcode，但需要 macOS Command Line Tools 提供 clang++。"
  echo "可检查：xcode-select -p"
  read -r -p "按回车退出..." _
  exit 3
fi

echo ""
echo "============================================================"
echo "剪映 Mac 本地工程打包 V4.3"
echo "============================================================"
echo "工程：$PROJECT_DIR"
echo "剪映：$JY_APP"
echo "原生库：$LIB"
echo ""
FRAMEWORKS_DIR="$(dirname "$LIB")"
LIBAGFX="$(find "$FRAMEWORKS_DIR" "$JY_APP/Contents" -type f -name "libAGFX.dylib" -print -quit 2>/dev/null || true)"
if [ -z "$LIBAGFX" ]; then
  echo
  echo "未找到 libAGFX.dylib"
  echo "已检查：$FRAMEWORKS_DIR"
  read -r -p "按回车退出..."
  exit 1
fi
echo "依赖库目录：$FRAMEWORKS_DIR"
echo "已找到 libAGFX.dylib：$LIBAGFX"
DYLD_DIRS="$FRAMEWORKS_DIR"
while IFS= read -r d; do [ -n "$d" ] && DYLD_DIRS="$DYLD_DIRS:$d"; done < <(find "$JY_APP/Contents" -type f -name "*.dylib" -print 2>/dev/null | xargs -n1 dirname 2>/dev/null | sort -u)
export DYLD_LIBRARY_PATH="$DYLD_DIRS${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
export DYLD_FALLBACK_LIBRARY_PATH="$FRAMEWORKS_DIR${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
export DYLD_FRAMEWORK_PATH="$FRAMEWORKS_DIR${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"

echo "正在调用剪映原生解密接口，请稍候……"
echo ""

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

cat > "$TMP_ROOT/decrypt.cpp" <<'CPP'
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
  if(argc!=4){std::cerr<<"usage: decrypt <dylib> <input> <output>\n";return 64;}
  try{
    void* h=dlopen(argv[1], RTLD_NOW|RTLD_GLOBAL);
    if(!h) throw std::runtime_error(std::string("dlopen failed: ")+dlerror());
    std::string in=readall(argv[2]);
    lvve::EncryptUtils c;
    c.enable(true);
    bool valid=false;
    std::string out=c.decrypt(in,"{}",valid);
    if(!valid || out.empty()) throw std::runtime_error("native decrypt returned invalid/empty result");
    writeall(argv[3],out);
    std::cout << out.size() << std::endl;
    dlclose(h);
    return 0;
  }catch(const std::exception&e){std::cerr<<"ERROR: "<<e.what()<<"\n";return 1;}
}
CPP

"$CLANG" -std=c++17 -O2 -Wl,-undefined,dynamic_lookup "$TMP_ROOT/decrypt.cpp" -o "$TMP_ROOT/jydecrypt" -ldl 2>"$TMP_ROOT/build.err"
if [ $? -ne 0 ]; then
  echo "原生桥接编译失败："
  cat "$TMP_ROOT/build.err"
  echo ""
  echo "这通常意味着当前 macOS 没有可用的 Command Line Tools，或本机剪映库架构与当前机器不匹配。"
  read -r -p "按回车退出..." _
  exit 4
fi

CANDIDATES_FILE="$TMP_ROOT/candidates.txt"
: > "$CANDIDATES_FILE"

while IFS= read -r -d '' p; do
  [ -f "$p" ] || continue
  base="$(basename "$p")"
  case "$base" in
    .DS_Store|*.db-shm|*.db-wal) continue ;;
  esac
  size="$(stat -f%z "$p" 2>/dev/null || echo 0)"
  [ "$size" -le 52428800 ] || continue
  ext="${base##*.}"
  ext_lc="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
  case "$ext_lc" in
    mp4|mov|mxf|m4v|avi|mkv|webm|mp3|wav|aac|m4a|flac|ogg|aiff|aif|jpg|jpeg|png|webp|heic|tif|tiff|gif|bmp|dng|arw|cr2|cr3|nef|raf|rw2|orf|sr2|braw|r3d|avif) continue ;;
  esac
  printf '%s\n' "$p" >> "$CANDIDATES_FILE"
done < <(find "$PROJECT_DIR" -type f -print0 2>/dev/null)

DECRYPTED_LIST="$TMP_ROOT/decrypted_list.txt"
: > "$DECRYPTED_LIST"

COUNT=0
SUCCESS=0
PLAIN_COUNT=0
DECRYPT_COUNT=0
TIMEOUT_COUNT=0
FAIL_COUNT=0

SORTED_CANDIDATES="$TMP_ROOT/candidates_sorted.txt"
"$PYTHON" - "$CANDIDATES_FILE" "$SORTED_CANDIDATES" <<'SORT'
import sys
from pathlib import Path

src,dst=sys.argv[1],sys.argv[2]
rows=[]
for raw in Path(src).read_text(encoding='utf-8',errors='replace').splitlines():
    p=Path(raw)
    n=p.name.lower()
    ext=p.suffix.lower()
    score=0
    if ext=='.json': score+=100
    if n.startswith('draft'): score+=50
    if 'timeline' in n: score+=45
    if 'material' in n: score+=45
    if n.startswith('template-'): score+=40
    if 'attachment' in str(p).lower(): score+=10
    if ext in ('.db','.sqlite','.sqlite3'): score-=1000
    if n.endswith(('.db-wal','.db-shm','.db-journal')): score-=1000
    rows.append((score,str(p)))
rows.sort(key=lambda x:(-x[0],x[1]))
Path(dst).write_text('\n'.join(p for _,p in rows)+'\n',encoding='utf-8')
SORT

"$PYTHON" - "$PYTHON" "$TMP_ROOT/jydecrypt" "$LIB" "$SORTED_CANDIDATES" "$TMP_ROOT" "$DECRYPTED_LIST" <<'DRIVER'
import sys, os, json, hashlib, subprocess, concurrent.futures
from pathlib import Path

PY=sys.argv[1]
DEC=sys.argv[2]
LIB=sys.argv[3]
LIST=Path(sys.argv[4])
TMP=Path(sys.argv[5])
OUTLIST=Path(sys.argv[6])

TIMEOUT=4.0
rows=[x for x in LIST.read_text(encoding='utf-8',errors='replace').splitlines() if x.strip()]

def valid_json(path):
    try:
        s=Path(path).read_text(encoding='utf-8-sig',errors='replace').strip()
        if not s: return False
        o=json.loads(s)
        return isinstance(o,(dict,list))
    except Exception:
        return False

def task(p):
    pp=Path(p)
    if valid_json(pp):
        return (p,p,'plain','ok',0.0)

    n=pp.name.lower()
    if pp.suffix.lower() in ('.db','.sqlite','.sqlite3') or n.endswith(('.db-wal','.db-shm','.db-journal')):
        return (p,'','skip_db','skip',0.0)

    digest=hashlib.sha1(p.encode()).hexdigest()[:16]
    out=TMP/f'dec_{digest}.json'
    log=TMP/f'dec_{digest}.log'
    err=TMP/f'dec_{digest}.err'
    try:
        r=subprocess.run(
            [DEC,LIB,p,str(out)],
            stdout=open(log,'w'),
            stderr=open(err,'w'),
            timeout=TIMEOUT,
            env=os.environ.copy(),
        )
        if r.returncode==0 and valid_json(out):
            return (p,str(out),'decrypted','ok',0.0)
        return (p,'','decrypt_fail','fail',0.0)
    except subprocess.TimeoutExpired:
        try:
            if out.exists(): out.unlink()
        except Exception: pass
        return (p,'','timeout','timeout',TIMEOUT)
    except Exception as e:
        return (p,'','exception:'+str(e),'fail',0.0)

results=[]
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
    futs=[ex.submit(task,p) for p in rows]
    for fut in concurrent.futures.as_completed(futs):
        results.append(fut.result())

results.sort(key=lambda x:x[0])
plain=dec=timeout=fail=skip=0
with OUTLIST.open('w',encoding='utf-8') as f:
    for p,out,kind,status,t in results:
        if status=='ok':
            f.write(f'{p}\t{out}\t{kind}\n')
            if kind=='plain': plain+=1
            else: dec+=1
        elif status=='timeout':
            timeout+=1
        elif status=='skip':
            skip+=1
        else:
            fail+=1

print(f'COUNT={len(rows)}')
print(f'PLAIN={plain}')
print(f'DECRYPT={dec}')
print(f'TIMEOUT={timeout}')
print(f'FAIL={fail}')
print(f'SKIP={skip}')
DRIVER

DRIVER_STATUS=$?
if [ "$DRIVER_STATUS" -ne 0 ]; then
  echo "工程数据扫描器异常退出（状态码：$DRIVER_STATUS）。"
  echo "原工程没有被修改。"
  read -r -p "按回车退出..." _
  exit 5
fi

DRIVER_STATS="$TMP_ROOT/driver_stats.txt"
"$PYTHON" - "$SORTED_CANDIDATES" "$DECRYPTED_LIST" "$TMP_ROOT" <<'STAT' > "$DRIVER_STATS"
from pathlib import Path
import sys
rows=[x for x in Path(sys.argv[1]).read_text(encoding='utf-8',errors='replace').splitlines() if x.strip()]
ok=[x for x in Path(sys.argv[2]).read_text(encoding='utf-8',errors='replace').splitlines() if x.strip()]
plain=sum(1 for x in ok if x.endswith('\tplain'))
dec=sum(1 for x in ok if x.endswith('\tdecrypted'))
print(f'COUNT={len(rows)}')
print(f'PLAIN={plain}')
print(f'DECRYPT={dec}')
print(f'SUCCESS={len(ok)}')
STAT

COUNT="$(grep '^COUNT=' "$DRIVER_STATS" | cut -d= -f2)"
PLAIN_COUNT="$(grep '^PLAIN=' "$DRIVER_STATS" | cut -d= -f2)"
DECRYPT_COUNT="$(grep '^DECRYPT=' "$DRIVER_STATS" | cut -d= -f2)"
SUCCESS="$(grep '^SUCCESS=' "$DRIVER_STATS" | cut -d= -f2)"

echo ""
echo "发现候选工程文件：$COUNT"
echo "直接读取的明文 JSON：$PLAIN_COUNT"
echo "原生解密得到的 JSON：$DECRYPT_COUNT"
echo "成功获得可解析 JSON：$SUCCESS"

if [ "$SUCCESS" -eq 0 ]; then
  echo ""
  echo "没有从工程中得到任何可解析的 JSON 草稿文件。"
  echo "原工程没有被修改。"
  read -r -p "按回车退出..." _
  exit 5
fi

export JY_CANDIDATE_COUNT="$COUNT"
export JY_JSON_SUCCESS="$SUCCESS"
export JY_JSON_PLAIN="$PLAIN_COUNT"
export JY_JSON_DECRYPT="$DECRYPT_COUNT"

echo ""

"$PYTHON" - "$PROJECT_DIR" "$DECRYPTED_LIST" "${CUSTOM_OUTPUT_DIR:-}" <<'PY' | tee "$TMP_ROOT/python_output.log"
import json, os, re, sys, shutil, time, urllib.parse, subprocess
from pathlib import Path
from collections import deque, defaultdict

project=Path(sys.argv[1]).resolve()
list_file=Path(sys.argv[2])
arg_custom=sys.argv[3] if len(sys.argv) > 3 else ''
env_custom=os.environ.get('CUSTOM_OUTPUT_DIR', '').strip()
custom_output_dir=arg_custom.strip() if arg_custom and arg_custom.strip() and arg_custom != 'undefined' else (env_custom if env_custom and env_custom != 'undefined' else None)

print("开始分析已获得的工程 JSON……", flush=True)

def load_any(p):
    try:
        raw=p.read_text(encoding='utf-8-sig', errors='replace')
    except Exception:
        return None
    try:
        return json.loads(raw)
    except Exception:
        x=raw.strip()
        if x.startswith('"') and x.endswith('"'):
            try: return json.loads(json.loads(x))
            except Exception: pass
        return None

roots=[]
lines=[x for x in list_file.read_text(encoding='utf-8',errors='replace').splitlines() if x.strip()]
for idx,line in enumerate(lines,1):
    parts=line.split('\t',2)
    if len(parts)<2: continue
    src,parsed=parts[0],parts[1]
    obj=load_any(Path(parsed))
    if obj is not None:
        roots.append((Path(src),obj))

if not roots:
    raise RuntimeError('没有可解析的工程 JSON')

all_roots=[obj for _,obj in roots]

ID_KEYS={
    'material_id','materialid','materialId',
    'local_material_id','localmaterialid','localMaterialId',
}
PATH_KEYS={
    'path','file_path','filepath','material_path','materialpath',
    'resource_path','resourcepath','local_path','localpath',
    'filePath','materialPath','resourcePath','localPath',
    'source_path','sourcePath','media_path','mediaPath',
    'file_url','fileUrl','url','uri','source_url','sourceUrl',
}
NAME_KEYS={
    'name','material_name','materialName','file_name','fileName',
    'display_name','displayName','original_name','originalName',
}
MEDIA_EXT={
    '.mp4','.mov','.mxf','.m4v','.avi','.mkv','.webm',
    '.mp3','.wav','.aac','.m4a','.flac','.ogg','.aiff','.aif',
    '.jpg','.jpeg','.png','.webp','.heic','.tif','.tiff','.gif',
    '.bmp','.dng','.arw','.cr2','.cr3','.nef','.raf','.rw2',
    '.orf','.sr2','.braw','.r3d','.avif',
}
AUDIO_EXT={'.mp3','.wav','.aac','.m4a','.flac','.ogg','.aiff','.aif'}

def norm_id(v):
    if isinstance(v,(str,int,float)):
        z=str(v).strip()
        return z or None
    return None

def _v43_timeline_material_ids(obj):
    found=set()
    q=deque([obj])
    seen=set()
    while q:
        v=q.popleft()
        if isinstance(v,(dict,list)):
            oid=id(v)
            if oid in seen: continue
            seen.add(oid)
        if isinstance(v,dict):
            for k,z in v.items():
                if k in ID_KEYS:
                    zz=norm_id(z)
                    if zz: found.add(zz)
                if isinstance(z,(dict,list)): q.append(z)
        elif isinstance(v,list):
            for z in v:
                if isinstance(z,(dict,list)): q.append(z)
    return found

def _v43_timeline_name(obj, fallback):
    if isinstance(obj,dict):
        for k in ('name','timeline_name','timelineName','title','display_name','displayName'):
            v=obj.get(k)
            if isinstance(v,str) and v.strip(): return v.strip()
    return fallback

_v43_candidates=[]
for _root_name,_root_obj in roots:
    _root_name=str(_root_name)
    if "/subdraft/" in _root_name or _root_name.startswith("subdraft/"): continue
    normalized=_root_name.replace("\\","/")
    if not re.search(r"(^|/)Timelines/[^/]+/common_attachment/attachment_pc_timeline\.json$", normalized):
        continue
    try: ids=_v43_timeline_material_ids(_root_obj)
    except Exception: ids=set()
    if not ids: continue
    name=_v43_timeline_name(_root_obj, Path(normalized).parts[-3] if len(Path(normalized).parts)>=3 else normalized)
    _v43_candidates.append({"path": normalized, "name": name, "material_ids": ids})

_v43_unique=[]
_v43_seen=set()
for _t in _v43_candidates:
    if _t["path"] in _v43_seen: continue
    _v43_seen.add(_t["path"])
    _v43_unique.append(_t)
_v43_candidates=_v43_unique

_v43_selected=None
if len(_v43_candidates) > 1:
    print("", flush=True)
    print("============================================================", flush=True)
    print("V4.3 检测到多个主时间线", flush=True)
    print("============================================================", flush=True)
    for _i,_t in enumerate(_v43_candidates,1):
        print(f"  [{_i}] {_t['name']}  (引用素材 {len(_t['material_ids'])} 个)", flush=True)
    print("", flush=True)
    while True:
        try:
            _choice=input("请选择要打包的主时间线编号（Q=退出）：").strip()
        except (EOFError,KeyboardInterrupt):
            raise SystemExit(0)
        if _choice.lower()=="q": raise SystemExit(0)
        if _choice.isdigit() and 1 <= int(_choice) <= len(_v43_candidates):
            _v43_selected=_v43_candidates[int(_choice)-1]
            break

def parse_nested_json(v):
    if not isinstance(v,str): return None
    x=v.strip()
    if len(x)<2 or len(x)>2_000_000: return None
    if not ((x.startswith('{') and x.endswith('}')) or (x.startswith('[') and x.endswith(']'))):
        return None
    try: return json.loads(x)
    except Exception: return None

def walk(x, max_nodes=2_000_000):
    q=deque([x])
    seen_objs=set()
    count=0
    while q and count<max_nodes:
        v=q.popleft()
        oid=id(v)
        if isinstance(v,(dict,list)):
            if oid in seen_objs: continue
            seen_objs.add(oid)
        yield v
        count+=1
        if isinstance(v,dict): q.extend(v.values())
        elif isinstance(v,list): q.extend(v)

print("阶段 1/5：扫描 material_id / 时间线引用……", flush=True)
used_ids=set()
material_refs=0
for ri,obj in enumerate(all_roots,1):
    for n in walk(obj):
        if not isinstance(n,dict): continue
        mids=[]
        for k,v in n.items():
            if k in ID_KEYS:
                z=norm_id(v)
                if z: mids.append(z)
        if not mids: continue
        path_hint=False
        keys=set(n.keys())
        if keys & {'target_timerange','source_timerange','track_type','trackType','render_index','renderIndex','start_time','startTime','segment','clip'}:
            path_hint=True
        if path_hint or any(str(k).lower() in ('segment','segments','clip','clips','track','tracks') for k in n.keys()):
            used_ids.update(mids)
            material_refs += len(mids)

if _v43_selected is not None:
    used_ids &= _v43_selected["material_ids"]

print("阶段 2/5：建立全工程素材索引……", flush=True)
material_by_id={}
material_score={}
material_name_by_id=defaultdict(set)

for ri,obj in enumerate(all_roots,1):
    for n in walk(obj):
        if not isinstance(n,dict): continue
        direct_ids=[]
        for k,v in n.items():
            if k in {'id','material_id','materialId','local_material_id','localMaterialId'}:
                z=norm_id(v)
                if z: direct_ids.append(z)
        keys=set(n.keys())
        has_media_signal=bool(keys & (PATH_KEYS|NAME_KEYS|{'type','material_type','materialType'}))
        if direct_ids and (has_media_signal or any(k in keys for k in PATH_KEYS|NAME_KEYS)):
            score=(5 if keys & PATH_KEYS else 0)+(3 if keys & NAME_KEYS else 0)+(2 if keys & {'type','material_type','materialType'} else 0)
            for mid in direct_ids:
                if score >= material_score.get(mid,-1):
                    material_score[mid]=score
                    material_by_id[mid]=n
                for k,v in n.items():
                    if k in NAME_KEYS and isinstance(v,str) and v.strip():
                        nm=Path(v.strip().replace('\\','/')).name
                        if Path(nm).suffix.lower() in MEDIA_EXT:
                            material_name_by_id[mid].add(nm)

print("阶段 3/5：解析素材本地路径……", flush=True)
PATH_TOKEN_RE=re.compile(
    r'(?:(?:file://(?:localhost)?/)|/Users/|/Volumes/|/private/var/|/tmp/|[A-Za-z]:[\\/])[^"\'\r\n]+',
    re.I
)

def add_path(raw,out,seen):
    if not isinstance(raw,str): return
    s=raw.strip().strip('"').strip("'")
    if not s or len(s)>4096: return
    for _ in range(2):
        try: z=urllib.parse.unquote(s)
        except Exception: z=s
        if z==s: break
        s=z
    if s.startswith('file://'):
        s=s[7:]
        if s.startswith('localhost/'): s=s[9:]
    s=s.replace('\\\\','/')
    s=re.sub(r'##_draftpath_placeholder_\[[^\]]+\]_##',str(project),s)
    s=s.split('?',1)[0].split('#',1)[0]
    if s.startswith('/') or s.startswith('~/') or re.match(r'^[A-Za-z]:/',s):
        if s not in seen:
            seen.add(s); out.append(s)

def candidate_paths(obj):
    out=[]; seen=set()
    q=deque([(obj,0)])
    seen_objs=set()
    while q:
        v,d=q.popleft()
        if d>6: continue
        if isinstance(v,(dict,list)):
            oid=id(v)
            if oid in seen_objs: continue
            seen_objs.add(oid)
        if isinstance(v,dict):
            for k,z in v.items():
                if k in PATH_KEYS and isinstance(z,str): add_path(z,out,seen)
                if isinstance(z,(dict,list)): q.append((z,d+1))
                elif isinstance(z,str) and k in {'source','extra_info','extraInfo','meta','value','data','resource','resource_info','resourceInfo'}:
                    nested=parse_nested_json(z)
                    if nested is not None: q.append((nested,d+1))
                    for m in PATH_TOKEN_RE.findall(z): add_path(m,out,seen)
        elif isinstance(v,list):
            for z in v: q.append((z,d+1))
    return out

def resolve(raw):
    if not raw: return None
    s=str(raw)
    if s.startswith('~/'): s=str(Path(s).expanduser())
    p=Path(s)
    if not p.is_absolute(): p=(project/p).resolve()
    try:
        if p.is_file(): return p.resolve()
    except OSError: pass
    return None

found={}
unresolved=[]
items=list(material_by_id.items())
for idx,(mid,m) in enumerate(items,1):
    paths=candidate_paths(m)
    resolved=None
    for raw in paths:
        resolved=resolve(raw)
        if resolved: break
    if resolved:
        found[str(resolved)]=(mid,m,mid in used_ids)
    else:
        names=set(material_name_by_id.get(mid,set()))
        for k,v in m.items():
            if k in NAME_KEYS and isinstance(v,str) and Path(v).suffix.lower() in MEDIA_EXT:
                names.add(Path(v).name)
        unresolved.append((mid,paths,sorted(names),mid in used_ids))

print("阶段 4/5：对未解析素材进行文件名二次定位……", flush=True)
name_to_ids=defaultdict(set)
for mid,paths,names,is_used in unresolved:
    for nm in names:
        if Path(nm).suffix.lower() in MEDIA_EXT:
            name_to_ids[nm].add(mid)

def mdfind_name(name):
    if not name or len(name)>512: return []
    q=name.replace('\\','\\\\').replace('"','\\"')
    query=f'kMDItemFSName == "{q}"cd'
    try:
        r=subprocess.run(['mdfind', query], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=3.0)
        return [x.strip() for x in r.stdout.splitlines() if x.strip()]
    except (subprocess.TimeoutExpired,OSError):
        return []

remaining=set(name_to_ids)
for nm in sorted(name_to_ids):
    if not remaining: break
    for raw in mdfind_name(nm):
        p=Path(raw)
        try:
            if not p.is_file() or p.suffix.lower() not in MEDIA_EXT: continue
        except OSError: continue
        mids=name_to_ids.get(p.name,set())
        if not mids: continue
        for mid in mids:
            found[str(p.resolve())]=(mid,material_by_id.get(mid,{}),mid in used_ids)
        remaining.difference_update(mids)

if remaining:
    try:
        for root,dirs,files in os.walk(project):
            dirs[:] = [d for d in dirs if d not in {'cache','Cache','Caches','draft_cache','DraftCache','thumbnails','Thumbnail'}]
            for fn in files:
                if fn not in name_to_ids: continue
                p=Path(root)/fn
                mids=name_to_ids.get(fn,set())
                for mid in mids:
                    found[str(p.resolve())]=(mid,material_by_id.get(mid,{}),mid in used_ids)
                remaining.difference_update(mids)
            if not remaining: break
    except (PermissionError,OSError):
        pass

print("阶段 5/5：开始复制剪映工程与素材……", flush=True)
stamp=time.strftime('%Y%m%d_%H%M%S')
name=re.sub(r'[/:*?"<>|]+','_',project.name).strip() or '剪映工程'

if custom_output_dir:
    out=Path(custom_output_dir).resolve()/f'{name}_{stamp}'
else:
    out=project.parent/f'{name}_{stamp}'
out.mkdir(parents=True,exist_ok=True)
print(f"OUTPUT_DIR={out}", flush=True)

project_out=out/name
video_assets=out/'画面素材'
audio_assets=out/'音频'
project_out.mkdir(parents=True,exist_ok=True)
video_assets.mkdir(parents=True,exist_ok=True)
audio_assets.mkdir(parents=True,exist_ok=True)

skip_dirs={'assets','Assets','materials','Materials','cache','Cache','Caches','draft_cache'}
def copy_skeleton(src,dst):
    for e in src.iterdir():
        if e.name in skip_dirs or e.name.startswith(name+'_'): continue
        if e.is_dir():
            nd=dst/e.name
            nd.mkdir(parents=True,exist_ok=True)
            copy_skeleton(e,nd)
        else:
            if e.suffix.lower() in MEDIA_EXT: continue
            try: shutil.copy2(e,dst/e.name)
            except OSError: pass

copy_skeleton(project,project_out)

def original_path_target(root, srcp):
    try: resolved=srcp.resolve()
    except OSError: resolved=srcp
    parts=[]
    for p in resolved.parts:
        if p in ('/',''): continue
        parts.append(re.sub(r'[:*?"<>|]','_',p))
    keep=parts[-4:] if len(parts) > 4 else parts
    return root.joinpath(*keep)

mapping={}
for src,(mid,m,is_used) in sorted(found.items()):
    srcp=Path(src)
    cat=''
    if isinstance(m,dict):
        cat=str(m.get('type') or m.get('material_type') or m.get('materialType') or '').lower()
    is_audio=any(x in cat for x in ('audio','sound','music')) or srcp.suffix.lower() in AUDIO_EXT
    target=audio_assets/srcp.name if is_audio else original_path_target(video_assets,srcp)
    target.parent.mkdir(parents=True,exist_ok=True)
    if target.exists():
        try: same = target.resolve() == srcp.resolve()
        except OSError: same = False
        if not same:
            i=2
            while True:
                candidate=target.with_name(f'{target.stem}_{i}{target.suffix}')
                if not candidate.exists():
                    target=candidate
                    break
                i+=1
    try:
        shutil.copy2(srcp,target)
        mapping[src]=target
    except OSError: pass

manifest=out/'V4.3.2_打包诊断.txt'
with manifest.open('w',encoding='utf-8') as f:
    f.write('剪映 Mac 本地工程打包 V4.3\n'+'='*78+'\n')
    f.write('画面素材路径规则：保留最后 3 个文件夹 + 文件名，去除前置盘符/绝对路径\n')
    f.write(f'原工程：{project}\n')
    f.write(f'工程 JSON：{len(all_roots)}\n')
    f.write(f'material 对象：{len(material_by_id)}\n')
    f.write(f'时间线引用 material_id：{len(used_ids)}\n')
    f.write(f'成功定位本地源文件：{len(found)}\n')
    f.write(f'实际复制文件：{len(mapping)}\n')
    f.write(f'输出目录：{out}\n')
    f.write(f'工程目录：{project_out}\n')
    f.write(f'画面素材目录：{video_assets}\n')
    f.write(f'音频目录：{audio_assets}\n\n')

    f.write('【已定位素材】\n')
    for src,(mid,m,is_used) in sorted(found.items()):
        f.write(f'[{mid}] {"时间线使用" if is_used else "草稿定义"}\t{src}\n')
        if src in mapping:
            f.write(f'包内：{mapping[src]}\n')

PY

PY_STATUS="${PIPESTATUS[0]}"
if [ "$PY_STATUS" -ne 0 ]; then
  exit "$PY_STATUS"
fi

OUTPUT_DIR="$(sed -n 's/^OUTPUT_DIR=//p' "$TMP_ROOT/python_output.log" | tail -n 1)"
[ -n "$OUTPUT_DIR" ] && [ -d "$OUTPUT_DIR" ] || exit 8
OUTPUT_PROJECT_DIR="$(sed -n 's/^工程目录：//p' "$OUTPUT_DIR/V4.3.2_打包诊断.txt" | tail -n 1)"
[ -n "$OUTPUT_PROJECT_DIR" ] && [ -d "$OUTPUT_PROJECT_DIR" ] || exit 9
[ -d "$OUTPUT_DIR/画面素材" ] || exit 9
[ -d "$OUTPUT_DIR/音频" ] || exit 9

echo ""
echo "============================================================"
echo "剪映 Mac 本地工程打包 V4.3.2 完成"
echo "============================================================"
echo "输出目录：$OUTPUT_DIR"
open "$OUTPUT_DIR" >/dev/null 2>&1 || true
