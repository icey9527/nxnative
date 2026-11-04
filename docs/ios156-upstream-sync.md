# 同步上游到 iOS 15.6 分支：踩过的坑与流程

这份文档记录 **`ios15.6` 分支每次 `git merge seedds/main` 之后会反复出现的失败模式**，
以及怎么在提交构建之前把它们堵住。

背景：上游主线只支持 iOS 26（Metal 4），我们的分支要为 iPadOS 15.6 编译
（legacy Metal / AIR 2.4 / a10x，ARMv8.0）。上游每往前走，都会带入**在 15.6 上不成立**的假设。

---

## 一、五类失败模式

### 类别 A：用了旧系统不存在的 API（最危险，会崩溃）

符号在旧系统上是**弱引用**，解析为 `NULL`。用在数据常量上就是**解引用地址 0**——
启动即 SIGSEGV，游戏自己的日志里什么都没有。

**已发生：**

| 位置 | 符号 | 需要 | 现象 |
|---|---|---|---|
| `dm/ios/Sources/main.m` | `UIWindowSceneSessionRoleExternalDisplayNonInteractive` | iOS 16 | 启动在 `application:configurationForConnectingSceneSession:` 崩溃（**发生过两次**） |
| `dm/ios/Sources/GameMenu.swift` | `UIAction.subtitle` / `UIMenu(subtitle:)` | iOS 16 | 编译期被 `-Werror=unguarded-availability-new` 拦下 |
| `dm/ios/Sources/Launcher.swift` | `contentMargins(_:_:for:)` | iOS 17 | 同上 |
| `dm/ios/Sources/Launcher.swift` | `Task.sleep(for:)` / `.seconds` | iOS 16 | 同上 |

**注意**：Swift 的能靠 `-Werror=unguarded-availability-new` 拦住；
**ObjC 的数据常量拦不住**（SDK 没给它们打 availability 标注），所以 `main.m` 那处两次都漏到了运行时。

### 类别 B：LSE 原子指令（汇编器直接拒绝）

目标 `a10x` 是 ARMv8.0，**没有 LSE**（`stadd`/`ldadd` 等）。

**已发生：** `dm/gfx/nvn/nvn_thunks.S` 有 9 处被内联成 `stadd`，
`dm/gfx/nvn/nvn_entry.S` 有 1 处，且 `gen_protos.py` 的模板会在
`__ARM_FEATURE_ATOMICS` 成立时生成 LSE 版本。

**修法**：一律改成 `ldxr/stxr` 循环，**生成器模板也要改**，否则下次重新生成会回退。

### 类别 C：legacy 渲染器缺符号（链接失败）

`nvn_mtl.m` 从第 ~158 行分成两半：上半是 legacy（含 `nvn_mtl_legacy.inc`），
下半是 Metal 4。上游新增的入口点常常只写在下半，而**公共代码**（`hle_nvn.c`、`hle_hid.c`）会调用它们。

**已发生：** `mtl_fb_stats`、`dm_gfx_restop`、`mtl_pool_gpu_written`、
`mtl_probe_ramp_on`、`mtl_prog_forget`、`front_screen_max_fps`。

**修法**：在 legacy 那半补"什么都不做"的桩。**不要靠碰运气**，用下面的脚本算全集。

### 类别 D：头文件/接口被上游改动（编译失败）

| 上游改动 | 我们的后果 | 修法 |
|---|---|---|
| `pso_key` 删掉 `topology` 字段 | legacy 有 5 处还在用 | 恢复我们的头文件（超集，现代分支不碰它） |
| `dm_set_game_image_header` 改成 `void` + `g_game_image` | 与我们 `g_module_image_mh` 是两套设计 | 保留我们的，删掉上游塞进 `front.h` 的重复声明 |
| `dmsh_build.py` 改走 `dmsh_pch` | 我们的旧 `ios_metal.py` 调用了它却没导入 | 改用上游版，只把 `-mios-version-min` 换回 `DM_IOS_MIN` |
| `hle_audio.c` 重写 | 丢掉了我们加的 `dm_audio_diagnostics` / `dm_audio_env_callback_set` | 在上游文件之上补回 |
| iOS SDK 不像 macOS 那样传递引入 `vm_map` | `loader.c` 的 `vm_allocate` 找不到声明 | 在文件顶部显式 `#include <mach/mach.h>` |

### 类别 E：我们自己的操作失误（最容易被忽视）

| 失误 | 后果 |
|---|---|
| 用正则替换「保留我方」来解冲突 | 把 `build_ipa.sh` 切断（第 286 行文件意外结束），另外 5 个文件无声改动 |
| 把 `{os.environ.get(...)}` 塞进**非 f-string** | 参数变成字面量，43 个着色器全部编译失败 |
| 逐条补链接错误 | 一轮 13 分钟，补了 9 轮 |

**结论：解冲突不要用文本替换，用 `git checkout <ref> -- <path>` 或逐块手工编辑。**
一类问题要一次算全集，不要一个个试。

---

## 二、标准同步流程

```bash
# 0. 准备
cd F:/nxnative/work-ios156        # 独立 worktree，别在主检出上做

# 1. 合入
git fetch seedds
git merge --no-commit --no-ff seedds/main

# 2. 冲突分流（按类别，不按文件）
#    dm/ios/Sources/**   → 整层取一侧！不要半层混合，混了就会缺符号
#    docs/ scripts/ games/ tools/tests/  → 取上游
#    dm/host/** dm/gfx/** → 逐块人工判断
git checkout <ours|theirs> -- <path>

# 3. 提交前自检（见第三节）

# 4. 构建，装，测
```

**第 2 步的关键教训**：`dm/ios` 只能整体取一边。
我们曾经「保留自己的 `front_ios.m`/`DmGamepad.m`，但新文件从上游进来」，
结果 `GameMenu.swift` 调用 `dm_setting_live`、`dm_pad_layout*`，
这些函数只在**上游版的 `front_ios.m`** 里，链接就缺 6 个符号。

---

## 三、提交构建之前必须跑的三项自检

### 1. iOS 15.6 可用性（防类别 A）

```bash
python3 F:/nxnative/ci/tools/check_ios156_apis.py dm/ios/Sources
```

CI 里已固化为一步，用不过就会在编译前失败。

### 2. LSE 与 legacy 缺符号（防类别 B、C）

```bash
grep -rn "^\s*stadd\|^\s*ldadd" dm/gfx/nvn/*.S            # 必须为空
python3 - <<'PY'                                          # legacy 缺哪些入口
import re
src=open('dm/gfx/nvn/nvn_mtl.m',encoding='utf-8').read().split('\n')
depth=0
for i,l in enumerate(src,1):
    s=l.strip()
    if s.startswith('#if'): depth+=1
    elif s.startswith('#endif'): depth-=1
    elif s.startswith('#else') and depth==1: split=i; break
legacy='\n'.join(src[:split-1])+'\n'+open('dm/gfx/nvn/nvn_mtl_legacy.inc',encoding='utf-8').read()
modern='\n'.join(src[split:])
d=lambda t:set(re.findall(r'^[A-Za-z_][\w \*]*?\b([a-z][a-z0-9_]*)\s*\([^;{]*\)\s*\{',t,re.M))
callers=''.join(open(f,encoding='utf-8').read() for f in ('dm/gfx/nvn/hle_nvn.c','dm/host/hle_hid.c'))
print(sorted(n for n in (d(modern)-d(legacy)) if re.search(r'\b'+n+r'\s*\(',callers)))
PY
```

### 3. 脚本语法（防类别 E）

```bash
for f in $(git ls-files '*.sh'); do bash -n "$f" || echo "语法错: $f"; done
python3 -m py_compile $(git ls-files '*.py' | head -50)
```

---

## 四、CI 里的自动防线

| 防线 | 位置 | 挡住什么 |
|---|---|---|
| `-Werror=unguarded-availability-new` | `dm/ios/tools/gen_build.py` | Swift/ObjC 中**有 availability 标注**的新 API |
| `check_ios156_apis.py` | CI 第 66 行 | ObjC **数据常量**（编译器拦不住的那类） |
| 弱引用符号扫描 | CI（构建后） | 列出所有弱引用，新出现的需人工确认 |
| AIR triple 断言 | CI | 着色器必须是 `air64-*-apple-ios15` |
| 链接失败打印符号表 + 上传 build.log | CI | 链接错了能直接看到符号，不用猜 |

---

## 五、给下一次的一句话总结

> 合并上游后，先跑三项自检（iOS 15.6 API、LSE/legacy 符号、脚本语法），
> 再提交构建。`dm/ios` 只能整层取一侧。解冲突用 `git checkout`，不要用正则替换。
