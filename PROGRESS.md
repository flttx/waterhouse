# 开发进度

## 2026-10-09 · 音效与动态 BGM（代码与自动验收完成）
- 用户确认混合制作（原创合成与免费授权录音）及克制的动态氛围配乐，并要求执行计划。
- 初始源码工作区干净；已有 13 个合成 WAV、单总音量、统一生物预兆和单环境底声。计划补齐分组混音、动作/设备、六组区域、八类生物与同步分层配乐。
- 素材、声音运行、音乐调度并行分工；主线接入实际角色/设备/生物事件、设置和验证。保持 AI 噪声与听觉混音独立。
- 声音系统、素材与 Windows 0.3 包已完成自动验收；真人耳机/扬声器整局试听不以自动回归冒充。
- 已实现四项音量与真实静音、28 世界 + 4 UI 声部、六组区域 2 秒过渡、介质 0.5 秒过渡，最近 8 个声源 5 Hz 实体射线遮挡（含泵），遮挡低通/衰减 0.3 秒平滑。世界音频与 AI 噪声事件独立。
- 角色 jump/land/splash/dive/surface/climb/hurt、设备中止/完成/压力/闸门、实际生物前摇与命中分别接入。伤害增加可选来源参数，保留原数值与条件；原测试替身同步接受来源参数，既有行为断言未删除。
- 素材 66 cues、83 音效 + 10 BGM、最终 15,465,573 字节；44 成品使用原站核实并下载的 Kenney CC0 / Michel Baradari CC BY 3.0 录音。111 条 SHA-256/出处/加工记录，来源见 `assets/audio/AUDIO_SOURCES.md`；原始录音 `.gdignore` 排除导入，Windows 包新增 AUDIO_CREDITS。
- 资产检查已通过：全部 48 kHz、声道/时长/循环接缝与能量、引用/归属、4 倍重建峰值；最高成品峰值 −5.14557 dBTP、最大循环跳变 0.0049644，报告 `artifacts/audio-assets-report.json`。
- `music_test.gd` 原生 WASAPI 44 项通过：同钟三层 96 秒、迟滞/留白、排水分层、流程 once、暂停真实播放位置、压低及重开；退出无错误。`audio_test.gd` 首轮 73 项通过，含真实墙遮挡/移除、实例跟随与独立预兆、前摇不伪造命中、池上限/低氧优先、旧配置新增默认、十次重开与终局声音。
- 实际 RTX3050 / WASAPI `audio_capture.gd` 两种窗口设置页六滑条、可见范围与首个控件焦点通过；已查看 1280×800 截图。真实 mixer 39.35 秒 / 48 kHz 立体声捕获，4 倍真峰值 −7.11 dBTP，FFmpeg EBU 测得 −27.5 LUFS / 13.3 LU 动态范围。捕获是脚本声音场景预览，不充当真人整局试听。原 game_flow 更新 Ogg 循环行为检查后仍 40 项通过。

### 第三阶段最终验证与交付
- 源码提交前规范化 Kenney 许可副本的异常换行与行尾空白，并同步生成器；许可文字未改变、原始 ZIP 未修改，111 条来源 SHA-256 与许可引用复核通过。提交前源码 lint、暂存区 whitespace、文件大小与生成物排除检查通过。
- 集成复审修复：诱饵碰撞归入 SFX，不再被环境音量误关；闸门阶段清除停用敌人的威胁，让撤离音乐及时出现；致死命中保留短身体冲击声，清理旧世界声音不再吞掉它；角色冻结期间停止伪脚步。排水音乐改为真实无掉音循环并纳入接缝/能量检查。设置回归升级为六滑条逐项验证，map_ui 62 项通过。
- 长程验证曾两次原生崩溃：Windows minidump 为 WASAPI 混音线程 read 0x40、0xc0000005 / 偏移 0x31d6c57。纯音频最小复现发生相同崩溃，相同代码加锁后 3000 万写入通过。官方 4.7.2 源码 set_bus_send 无锁修改 StringName，混音线程并发查发送目标，空指针窗口与 dump 一致：[AudioServer](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/servers/audio/audio_server.cpp)、[StringName](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/string/string_name.cpp)。生产路由加 lock/unlock 并跳过同目标重复赋值，新增项目 AGENTS Never 约束和路由压力回归，不关音频、不忽略失败。
- 修复后完整通关两次通过：54 项 / 十设备 / 9 次真实 E 上岸 / fallback0 / 1990.30m / health100 / 最低氧62.40%；单跑 922.30 模拟秒、111.39 wall 秒，最终完整检查 922.03 模拟秒、111.36 wall 秒。敌人仍仅在静态通行回归中禁用。
- 最终 tools/export_windows.ps1 exit0：17 运行脚本解析、19 回归入口、300 帧运行、93 素材 / 66 cues / 10 配乐 / 111 来源、源码 lint 与 Git whitespace 全部通过，见 artifacts/audio-delivery.log。音乐专项最终 46 项；声音专项补测最终 80 项（audio-test-final.log）；生产 _send 活跃 WASAPI mixer 300 万次切换通过（audio-routing-test.log）。
- 最终实机两窗口设置均已查看：39.51 秒 / 48 kHz 立体声 WAV，4 倍真峰值 −8.00 dBTP、RMS0.04046，另提供 MP3 试听。证据 audio-capture-final.log、audio-mix-report.json。脚本场景预览不代表完整真人试听。
- Windows 0.3 实际文件版本 0.3.0.0：EXE109158400 字节、PCK66549432 字节、ZIP103447781 字节。从 build 目录独立 EXE / RTX3050 / WASAPI 游戏运行 300 帧 exit0，无引擎错误。隔离 PCK 审计解码全部 93 声音资源，原录音目录未被打包；ZIP 五文件 CRC、CC BY 作者/许可链接、0.3 操作说明通过。证据 release-audio-gpu.log、package-audio-test.log。发布 EXE 拒绝 --path 覆盖是模板限制；PCK 审计使用本机 Godot 的 --main-pack，源码调试仍用编辑器 F5。

### 第三阶段后续
耳机与普通扬声器完整试玩探索/求生，确认八种生物听辨、预警方向、音乐掩蔽和循环疲劳，再按记录调整混音。合成呼吸与原创配乐的美术质感仍需人工试听及精修。

## 2026-10-08 · 首次源码提交准备
- 已确认本地 Git 与 `origin`（`https://github.com/flttx/waterhouse.git`）可用，远程尚无分支；沿用当前 `master` 分支进行首次提交。
- 纳入源码、场景、运行素材、Godot `.uid` / `.import` 设置、测试与工具；`.gitignore` 排除 `.godot/`、`build/`、`artifacts/` 和日志等生成文件。
- 本次源码 lint、暂存区 `git diff --cached --check`、文件大小与提交范围检查通过；修正一处测试文件末尾多余空行，没有修改游戏运行逻辑。已核对上一阶段完整 Godot 验证通过记录。

## 2026-10-08 · 第二阶段整设施扩展
- 用户要求更大场景、地图、人物目标提示、难度选择和更多怪物。
- 用户追加指出Web版的大地图、多怪物与成熟小地图模式；已按该参考将早期两翼/七设备/三怪物临时方案扩为完整设施。
- UI沿用当前青蓝/琥珀/低饱和视觉，不重做风格。地图显示设施与设备，不显示敌人位置。难度在新局开始时应用，避免中途切换破坏运行状态。
- 当前实现：约308×168m，19真实区域/28320㎡，10水域、16梯、深24m；档案/过滤/四边输水渠/阶梯浴场/溢流潜水塔/地下库/原主厅与撤离通道。
- 生物8类9实例：21.6m利维坦、6m鮟鱇、5m蟹、27.4m盲鲸、17.9m巨口、Hunter、Lurker、两群Drifter。前五类原GLB，后三类原生有机ArrayMesh。蟹原烘焙动画实机卷骨，使用原骨架八足IK修复，未伪造新模型生成。
- 十设备：配电→主池两阀→西档案联锁→东过滤调压→阶梯/溢流/水库三阀→泵→85秒压力→闸门→真实步行撤离。
- 三档呼吸100/60/45s、诱饵5/3/2、感知/速度/伤害/前摇差异；每档全部实际AI，新局应用/标题保存。探索实时80m小图与路线/敌人高差，求生下一方向与动作，深渊隐藏导航。M全图暂停，+/-缩放。路线使用262真实节点边验证、16梯弧线、胶囊/地面/水域过滤。

### 第二阶段验证
- `tools/check.ps1`：2026-10-08最终exit0，16个运行脚本解析、16个回归入口、300帧运行、源码lint全部通过；摘要 `artifacts/checks-expansion.txt`。检查使用Windows WASAPI：默认headless的Dummy音频退出会残留WAV playback，对照真实mixer不残留，未删除错误检查。
- `full_facility_traversal.gd`：54项通过，十设备全部真实射线/按住E，9次真实E上岸、climb fallback0；17074步、1990.30m、922.17模拟秒；最低氧62.4%、health100；真实等待压力、门动画、步行胜利。探索呼吸100s，只禁用敌人验证静态通行，不传送或覆盖设备/阶段/压力/生命/氧气，不等同真人15分钟通关。
- `all_creatures_test.gd`：41项、120.02模拟秒/7201步、9实例8种，真实shape margin0全部无穿透、Hunter276m无持续停滞、全actor暂停/恢复/重置/实时marker通过；真实mixer日志 `artifacts/all_creatures_wasapi.log`。
- `hazard_test.gd`：54项通过，阻挡听声衰减、零音量不调查、reset清除缓存，Hunter连续可见/逃跑+反复噪声20.000s退去。声场与水下雾插值增加上限，防低帧率/加速运行NaN。
- `map_ui_test.gd`：56项通过；`navigation_test.gd`：45项、262/262边、16/16梯、10实体接近位置，11路线梯转换。实际GPU两窗口标题/导航/全图共6张捕获，small生物高差按真实camera计算且两窗口均以GPU红像素验证3个chevron。
- `expansion_game_test.gd`：headless40项、实际GPU41项，通过三档参数/AI存在、模式切换、MAP暂停及关闭后鼠标捕获、死亡全部冻结与新局状态。`game_flow.gd`扩为40项，保留原闸门/重试约束并加入档案/过滤/三外池完整阶段锁。
- 原利维坦25项、实际main world10项保留通过；新Stalker46项、五类同时25项、giants actual24项通过；原五设备路径54项、5697步仍通过。
- 新区实走两翼5750步、外围10368步，全部新增梯/通道/潜水塔双向坡道/三池下潜上浮/296m横渠可通。GPU世界独立8视角100帧预热54–62FPS仅世界，不冒充整游戏稳定FPS承诺。
- UI/美术独立审查：下一步文字与箭头冲突、高差跳过小生物均修复并被审查确认resolved。Hunter/Lurker眼窝、牙长、哑光与口腔遮挡修复后实机可读，但审查仍判其牙根/嘴缘组织过渡partial；属于明确未完成的美术精修项，不宣称整游戏视觉验收全通过。截图 `game_ui_*.png`、8种preview与 `hunter_in_game.png` / `lurker_in_game.png`。
- 本轮Windows0.2新包已导出：EXE109158400字节、PCK58916392字节；独立EXE实际GPU240帧游戏运行exit0、无日志错误，见 `artifacts/export-expansion.log` / `release-expansion-gpu.log`。新ZIP97908411字节，四文件全包CRC通过，PLAY.txt已同步M/缩放/三档/十设备说明，不再沿用第一阶段旧包。

### 第二阶段后续
真人盲玩确认9敌人同时的难度、首次时间、迷路与死亡原因；升级Hunter/Lurker口部组织与皮肤到独立模型美术，继续检查长尾急转贴障碍。Steam SDK/商业素材授权与录制foley尚未完成。

## 2026-10-08 · 初始化
- 当前 Godot 目录为空；本机 Godot 4.7.2 可用。
- 参考项目 `E:\Projects\water-room`：Three.js 水房、阀门逃生、程序声音、Tripo GLB 模型。
- 不存在 `.codegraph/`；未创建索引。引用的 workflow.md 与 OMC 工具不可用，采用本地计划和原生子 Agent 分工。
- 渲染：Compatibility + MSAA，避免限制普通 Windows GPU；程序材质、雾、水下屏幕效果及少量动态阴影。
- 并行模块接口：水面 0m，甲板 0.65m，84m 长主池，26m 高拱顶，脚底角色坐标。

## 已完成 · 第一轮可玩集成
- 原生主/世界/角色/巨兽场景；84m 主池、26m 拱顶、东西侧室、断桥、四处梯子、水下阀门掩体。
- 双介质角色：奔跑/体力、可阻挡蹲伏、视角游泳/下潜/上浮、60秒呼吸、原生扫掠攀梯、手电与镜头设置。
- 21.6m 巨兽：复用 Web 项目的现有纹理与34根骨骼；原 march 动画不适合水生运动，改为沿历史脊柱路径摆动。头部1.7m球碰撞、原生水下 AStar3D 导航、视线遮挡、灯光与噪声感知，巡游/调查/搜索/追逐/退场。
- 五设备完整顺序：配电 → 两泄压阀 → 泵 → 85秒压力 → 北侧闸门。死亡/重开/暂停/结局与键盘聚焦菜单。
- 三枚有真实抛物线/碰撞声音的金属诱饵，13个离线原创程序WAV，空间衰减/混响/水下低通，跨水面雾与镜头过滤。
- Windows x64 导出预设、启动脚本、验证脚本、素材来源说明、PRD与操作说明。

## 验证记录 · 最终全部通过
- `godot_console --version`：4.7.2.stable.official.ed1daf0bf。
- Godot headless import、运行脚本 parse、原生300帧smoke：已执行，当前集成可启动。
- `tests/player_physics.gd`：41项通过，含实际4梯子；最初发现协程异常可能仍exit0，已增加资源检查/完成哨兵/watchdog。
- `tests/creature_test.gd`：25/25通过；唯一初期浮点边界误差改为有单位精度容差，不删除行为断言。
- `tests/game_flow.gd`：34/34通过；修复循环声音、菜单延迟聚焦、重开遗留Tween。销毁音频后等待实际mixer tick，清除退出资源提示。验证开门后仍需实际走进撤离通道。
- `tests/traversal_test.gd`：从真实出生位置连续输入5697个物理步，54项通过，5个真实2.8m设备ray命中，实际设备开门/Tween后步行穿过出口，脚位置z=-53.03686触发WON；身体与相机零穿墙。没有用传送替代通行验证。静态通行测试禁用巨兽，与遭遇回归分开。
- `tests/creature_world_test.gd`：10/10通过，实际世界120.02模拟秒，40倍time_scale配2400Hz保持1/60s物理步长；669导航点、263.1m运动、最长停滞0.13s。两阀声源与实际遮挡自然触发追逐/搜索/退去。1.7m头球零实体穿透；导航额外0.08m余量接触独立记录，不当成实体穿透。
- NVIDIA RTX3050 / OpenGL Compatibility实际GPU截图：`artifacts/title.png`、`waterhouse.png`、`underwater.png`、`leviathan.png`、`escape_passage.png`，已逐张查看，无shader错误。后续静态批处理完成；抓图中的30FPS包含同步读图，不作为稳定性能结论。
- `python tools/lint_sources.py`：通过。项目原为空目录，没有Git仓库；`git diff --check`不可用，源码空白检查由lint执行。
- 最终Windows x64 release EXE+PCK导出成功；独立EXE headless300帧、GPU标题180帧、GPU实际游戏180帧均 exit0、日志无错误。见 `artifacts/export.log`、`release-smoke.log`、`release-gpu.log`、`release-play-gpu.log`。
- 静态建筑优化：97个局部MultiMesh批次。RTX3050、1440×900/VSync off、预热90+测180帧；环境独立样本南甲板drawcall1311→670，池面1185→641，水下702→398。原91碰撞shape与6912Box角点指纹完全一致；新出口通道为此后单独的设计修复，不包含在这份优化对照指纹中。不能把该环境独立帧间隔作为整局FPS承诺。
- 收尾检查发现原北侧闸门后为整面墙：改成真实墙洞与10m撤离通道。开门只恢复移动，玩家走过z=-53的阈值才完成结局；流程与连续出口通行回归均已通过。
- 最终 `tools/check.ps1` exit0：导入、8个运行脚本parse、5套共164项回归、300帧运行与源码lint通过；完整摘要 `artifacts/checks.txt`。
- `build/TheWaterhouse-Windows-x64.zip` 已交付，内含EXE、PCK、PLAY.txt与直接由本机引擎导出的版权/许可证信息；标准库zipfile全包CRC检查PASS。不修改Web参考工程、不安装插件、不进行网络发布。

## 已知边界
- 10–15分钟为首次探索目标，未用真人盲玩验证；自动快速路线不能证明恐怖感、手感或最终节奏。
- Compatibility采用作者定义灯条的解析反射与ReflectionProbe，不是完整屏幕空间反射/折射或体积雾。
- 巨兽使用头部碰撞和曲线骨骼，尾部不是逐骨刚体；需要人工检查极端转弯附近的身体穿插。
- 音效是程序合成的可玩资源；商业美术、录制foley、原模型商业授权确认、Steam SDK均是后续任务。

## 下一步
第一、第二阶段实现、自动验收与Windows包已完成。下一步以真人盲玩记录整设施首次通关时长、九实例合并下的死亡原因、迷路点与不舒适镜头，调节追逐/亮度/耗氧；优先精修Hunter/Lurker口部组织，再做商业音画与素材授权确认。
