# 素材来源与用途

## 现有模型

以下五个 GLB 直接复制自用户指定的 `E:\Projects\water-room\public\models`，保留原始模型资源：

| 本工程资源 | 当前用途 |
| --- | --- |
| `models/leviathan_rig.glb` | 21.6 米主池利维坦 |
| `models/angler.glb` | 6 米过滤池鮟鱇 |
| `models/crab.glb` | 5 米岸上八足巨蟹，原生足部 IK |
| `models/whale.glb` | 27.4 米听音盲鲸，仅凭声音感知 |
| `models/colossus.glb` | 17.9 米多眼巨口，浮现与触臂攻击前摇 |

参考项目的 `src/creatures/tripo.js` 与 `tools/blender/tripo_rig_process.py` 提供原有 Tripo / Blender 处理线索。本轮只复用已有 GLB，没有调用 Tripo 重新生成，也没有进行新的 Blender 优化；这些线索不代替素材授权记录。

当前主生物使用 leviathan_rig 的 34 根现有骨骼和原始贴图；根据池内路径使用原生 Skeleton3D 重新计算水生脊柱运动。原预设动画为 march，未直接当作游泳动画播放。whale 已作为实际生物接入设施。

在商业发行前，需由素材账户所有者确认原生成账户的商业使用条款及项目素材权利。

## 本轮原创资源

- 3D 水房建筑、设备、管线、梯子、标牌：Godot 原生网格与场景节点。
- Hunter、Lurker、Drifter：本轮原创原生有机 ArrayMesh 与 shader；分别实现渠中巡游/有限追击、锚定针齿威胁、开放伞群与毒触须。Drifter 有两群实例，后三类没有导入 GLB。
- 8 个 Godot shader：建筑表面、水面、水下镜头及各类生物皮肤。
- 13 个 WAV：标准库程序合成，源码为 `tools/generate_audio.py`。
- 图标：项目原创 SVG。
- 中文字体：通过 Godot SystemFont 使用目标系统的微软雅黑/Noto CJK；不复制或分发系统字体文件。

本轮没有新增外部模型或音频来源。五个原 GLB 的商业使用权仍需素材账户所有者确认。
