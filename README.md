# 深渊水房 / The Waterhouse

Godot 4.x + GDScript 原生第一人称恐怖潜行垂直切片。探索废弃蓄水设施，完成十个设备目标，启动排水泵，并从北侧闸门逃离。本轮对照 Web 版扩为约 308×168 米的设施：19 个可探索区域、区域面积合计 28,320 平方米、10 处水域、16 处上岸梯，最大水深 24 米。档案库、过滤池、环形输水渠、阶梯浴场、北侧溢流池与潜水塔、黑水地下水库都有真实建筑与通行路径。

八类、九个生物实例分布于不同区域：利维坦、鮟鱇、八足巨蟹、听音盲鲸、多眼巨口、Hunter、Lurker，以及两群 Drifter。灯光、游泳和设备噪声会暴露位置；利用遮挡、慢速移动和金属诱饵脱身。

## 运行

已用 **Godot 4.7.2 / Windows x64** 验证。项目采用 Compatibility 渲染，不需要 Godot 插件、联网服务或额外 GDScript 库。

在 Godot 项目管理器导入 `project.godot`，打开后按 F5 运行。也可在 PowerShell 执行：

```powershell
.\run.ps1            # 标题界面
.\run.ps1 -Play      # 直接进入游戏
.\run.ps1 -Editor    # 编辑器
```

Windows 0.4.1 独立包已更新为 `build/TheWaterhouse-Windows-x64.zip`，通过导出、独立 GPU 运行、PCK 声音资源与 ZIP CRC 检查。解压后双击 `TheWaterhouse.exe`，保留同目录 `.pck`；普通玩家无需安装 Godot。包内附中文操作说明、引擎许可证与声音素材鸣谢。开发导出需与引擎相同版本的 Windows 导出模板。

源码调试使用 `run.ps1 -Editor` 后按 F5，可用 GDScript 断点与 Remote 场景树查看运行状态。建筑与设备仍由脚本在运行时组装，编辑器静态场景不代表完整设施。

## 操作

| 按键 | 操作 |
| --- | --- |
| WASD / 方向键 | 移动，水中沿视角游泳 |
| 鼠标 | 观察 |
| Shift | 奔跑 / 快速游泳，会消耗体力并增加声音 |
| 按住 C / Ctrl | 蹲伏 / 下潜 |
| Space | 跳跃 / 上浮 |
| 按住 E | 操作眼前设备 |
| E | 近水面梯子上岸 |
| F | 开关手电，灯光会暴露位置 |
| Q | 投掷金属诱饵，声音在实际碰撞处发生 |
| M | 打开 / 关闭设施全图，浏览时暂停游戏 |
| + / - | 缩放探索模式的小地图；支持数字键盘加减 |
| Esc | 暂停；可调音量、亮度、灵敏度与镜头起伏 |

浮出水面恢复呼吸。受追踪时，绕过水下隔墙比一直冲刺更有效。岸边梯子有标识；上岸前须浮到水面附近。死亡后可重新开始，设备、诱饵与生物状态一起重置。

## 难度与导航

标题界面选择难度并持久保存，在新局开始时应用；当前局不能中途修改。三档保留全部生物 AI，并调整感知、移动速度、攻击伤害与前摇。

| 难度 | 水下呼吸 | 金属诱饵 | 导航 |
| --- | --- | --- | --- |
| 探索 | 100 秒 | 5 个 | 默认视宽 80 米、玩家居中、北向的小地图；真实路线、怪物位置及高差，支持缩放 |
| 求生 | 60 秒 | 3 个 | 真实路线的下一方向，以及爬岸、下潜、上浮、补氧提示 |
| 深渊 | 45 秒 | 2 个 | 隐藏目标导航 |

M 设施全图在所有难度可查，只有探索显示怪物和路线。导航使用作者路径节点与 AStar3D，并检查角色胶囊、地面支撑和水域；目标文字方向与路线箭头一致。

## 逃生路线

1. 东侧配电间恢复维护电源。
2. 下潜关闭主池南、北两处泄压阀。
3. 西侧档案库解除安全联锁。
4. 关闭东侧过滤池调压器。
5. 关闭阶梯池、北溢流池、黑水地下库三处泄压阀，三者可在本阶段内任选顺序。
6. 西侧泵房启动排水控制，等待 85 秒建立压力。
7. 手动打开北侧闸门，步行穿过撤离通道，跨过北端出口进入结局。

完整设施自动通行回归已通过实际移动、E 操作和梯子上岸完成十设备链，未传送角色；一次记录为 1,990.3 米、922.15 秒模拟时间（约 15.37 分钟）。该测试使用探索的 100 秒呼吸并仅禁用敌人，用于静态可达性验收。实际首次游玩时长、九个生物合并后的难度平衡和长时间贴障碍行为仍待人工体验。

## 检查和导出

```powershell
.\tools\check.ps1
.\tools\export_windows.ps1
```

源码检查需要 Python 3（标准库，无额外包）、PATH 上的 FFmpeg/FFprobe 和 Godot 4.7.2 Windows；游戏本体不需要 Python 或 FFmpeg。检查包含资源导入、脚本解析、原生角色物理、生物感知与导航、地图及难度、十设备流程、实际关卡通行、生物实景、音频/配乐/活跃路由回归、声音来源/循环/峰值检查和运行冒烟，以及源码空白/调试输出 lint。原生 Godot 导入可能在解析错误时返回 0，检查脚本同时检查错误日志。

Windows 检查默认使用 WASAPI 音频驱动。Headless 的 Dummy 音频在退出时可能产生 WAV 资源泄漏报告；实际运行与脚本错误仍按失败处理。

GPU 视觉回归（需要图形桌面）：

```powershell
godot_console --path . --script tools/capture.gd
```

实际图片保存在 `artifacts/`。设施 UI 证据为 `game_ui_*_1280x800.png` / `game_ui_*_1440x900.png`，生物为各 `*_preview.png`；`waterhouse.png` 是第一阶段截图。

## 巨兽全身通行 · 0.4.1

利维坦与盲鲸按完整身体宽度规划路径，连续胶囊包络检查身体和尾鳍；不安全的移动会回退并重新规划。原模型全部顶点、UV与纹理保留，启动时重绑局部纵向骨链，修复自动蒙皮的远轴权重和急转时历史路径截角。身体保留受约束的游泳摆动。

新增 `tests/tail_clearance_test.gd` 在真实设施内反复反向、俯仰转向，按实际蒙皮矩阵审计两只巨兽的完整网格，同时检查持续移动与停滞。`--capture` 可生成隐藏水面的诊断俯视图，不改变正式游戏水面和灯光。

```powershell
godot_console --headless --audio-driver WASAPI --path . --script tests/tail_clearance_test.gd
godot_console --audio-driver WASAPI --path . --script tests/tail_clearance_test.gd -- --capture
```

## 遭遇与重点空间 · 0.4

主动猎手共享追击名额：探索/求生最多一只，深渊最多两只；漂浮群落仍是接触危险。持续暴露会先触发生物预兆，再进入追击。脱险后分别留出 10/7/4 秒喘息，上一只猎手额外让位 3 秒；暂停冻结计时，新局清空记录。

主巨兽的听声现在受实体障碍衰减；Hunter 丢失视线后可被强金属诱饵引走。普通游速或更慢且关闭手电时，利维坦、鮟鱇和巨蟹的视觉觉察积累降低；这是角色灯光/速度规则，不是实时环境照度测量。利维坦与盲鲸急转时降低推进速度，长尾仍沿历史路径摆动，没有新增逐骨刚体碰撞。

主水房检修桁架、首次下潜区深度标识与悬浮颗粒、地下库吊具和局部维修照明增强空间识别；表面加入破碎湿斑及浅水焦散。视觉装饰保持原有碰撞和通行路线。

```powershell
godot_console --headless --audio-driver WASAPI --path . --script tests/encounter_test.gd
godot_console --audio-driver WASAPI --path . --script tests/visual_polish_test.gd
```

后一个命令输出三处原生场景截图到 `artifacts/polish_*.png`；截图使用实际手电参数但不含 HUD 后期，不替代真人整局体验。

## 声音与动态配乐 · 0.3

新增 66 个声音事件、83 份音效和 10 份配乐素材：四类材质脚步、游泳/潜水/浮出/爬梯/呼吸、设备操作与中止、六组区域环境，以及八类生物各自的预兆、攻击前摇和实际命中声音。28 个世界瞬时声部与 4 个界面声部限制声音叠加；最近八个位置声源每秒五次检测实际障碍遮挡，包括泵。混音与 AI 听声规则独立。

总音量、音效、环境、音乐在设置中分别控制，零值完全静音；旧设置保留并为新增项使用默认值。跨区域两秒淡化，水上/水下半秒过渡。暂停和地图冻结声音与配乐进度，菜单反馈继续可用。

配乐采用三层同时间轴的 96 秒原创音轨，使用 Godot 原生同步播放器。平静探索留白 20–45 秒，危险持续后逐渐增加纹理与脉冲；前摇、缺氧和关键设备声音会压低音乐。首次下潜、地下水库、排水、撤离及结局有短段落，重新开始会重置触发记录。

44 份成品实际采用 Kenney CC0 和 Michel Baradari CC BY 3.0 录音，其余为原创合成；呼吸素材仍为合成。作者、来源、许可证、加工方式和 SHA-256 见 `assets/audio/AUDIO_SOURCES.md` 及 `audio_v2_manifest.json`，Windows 包携带 `AUDIO_CREDITS.txt`。旧 13 个合成 WAV 与生成器保留为历史资源。

素材加工需要 Python 3 与 PATH 上的 FFmpeg/FFprobe，无额外 Python 包；生成时使用仓库内原录音，运行游戏无需这些工具或联网。

```powershell
python tools/generate_audio_v2.py
python tools/check_audio_assets.py
godot_console --audio-driver WASAPI --path . --script tests/audio_capture.gd
python tools/check_audio_mix.py
```

实机脚本会捕获两种窗口的设置界面及一段约 39 秒的混音，保存在 `artifacts/audio_settings_*.png` 与 `audio-mix-preview.wav`。脚本刻意切换声音场景，用于验收混音，不是完整关卡通关录像。声音机制、资产及峰值自动验证通过后，仍需耳机/扬声器整局试听确认方向、重复疲劳和恐怖节奏。

## 工程

- `scenes/`：Godot 原生主场景、世界、角色和生物。
- `scripts/world.gd`：模块化建筑、真实碰撞、灯光和材质组装。
- `scripts/player.gd`：原生 CharacterBody3D 双介质物理。
- `scripts/leviathan.gd`：原生水下 AStar3D、遮挡感知、状态机与骨骼脊柱运动。
- `scripts/stalker.gd` / `whale.gd` / `colossus.gd` / `hazard.gd`：分区生物感知、动作、追击和伤害。
- `scripts/game.gd` / `device.gd`：目标约束、交互、压力计时、死亡与结局。
- `scripts/hud.gd` / `navigation_hud.gd` / `facility_map.gd`：中文界面、难度、路线小地图和暂停全图。
- `scripts/facility_navigation.gd` / `difficulty.gd`：真实通行路线及三档难度参数。
- `scripts/soundscape.gd`：跨介质空间声音。
- `shaders/`：水面、材质、骨骼皮肤与水下屏幕效果。
- `tests/`：无第三方测试框架的 Godot 原生回归。

素材来源见 `assets/ASSETS.md`，实现与验证记录见 `PROGRESS.md`。该切片尚需真人体验、音效精修和商业素材授权确认，尚未进行 Steam SDK 集成。
