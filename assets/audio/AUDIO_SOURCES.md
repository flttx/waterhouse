# Waterhouse 声音素材来源（v2）

所有素材均在本项目内离线处理；游戏运行无需网络、账号或音频服务。原有 13 个 WAV 和旧生成脚本保留。新素材清单、每个文件的 SHA-256、来源父文件及加工方式记录于 `audio_v2_manifest.json`。

## 第三方录音

| 素材 | 作者及原始来源 | 授权 | 实际使用与加工 |
| --- | --- | --- | --- |
| Impact Sounds 1.0 | Kenney — [原作者资产页](https://kenney.nl/assets/impact-sounds) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | 四类脚步、攀爬、落地、金属应力、管道、阀门、闸门停止与六组环境；选择原始 concrete / metal / plate / bell 录音，再变调、滤波、包络和归一化 |
| Water splashes | Michel Baradari，qubodup 提交 — [原始作品页](https://opengameart.org/content/water-splashes) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) | 两份 splash WAV 用于湿地脚步、游泳、快速游泳、入水、潜水、浮出、滴水及六组环境；单声道转换、重采样、截取、变调、滤波、叠层和归一化 |

两组来源于 **2026-10-09** 在原站核实授权并直接下载，无需登录。原始下载地址：

- [Kenney 官方 ZIP](https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip)
- [Water splashes 原站 7z](https://opengameart.org/sites/default/files/splash.7z)

原始档案、实际使用的原始录音、Kenney 包内许可证和 Water splashes 归属/授权说明保存在 `v2/source/`。Water splashes 的完整授权法律文本可从上述 Creative Commons 链接访问。发布游戏时应携带本文件和 `v2/source/WATER_LICENSE.txt`，或将同等归属说明加入鸣谢；CC0 不强制署名，但本项目保留 Kenney 鸣谢。修改不表示原作者认可本游戏。

**可直接用于游戏鸣谢的归属文字：**

> “Water splashes” by Michel Baradari, from OpenGameArt.org, licensed under CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/). Modified for The Waterhouse: mono conversion, resampling, editing, pitch/filter processing and layering. Impact Sounds by Kenney (kenney.nl), CC0.

## 原创合成

八类生物的预兆、攻击前摇和命中声，以及呼吸/吸气/受伤、机械启动/循环、潜水底声、心跳、界面反馈与全部配乐，由 `tools/generate_audio_v2.py` 确定性合成。合成呼吸不是真人录音，合成生物不包含未经授权的动物录音。六组环境与湿地脚步混合了上述两套已授权录音，因此仍保留 CC BY 3.0 归属；详细父文件见清单。

配乐包含 60 BPM、4/4、严格同步 96 秒的 base / texture / pulse 三层，32 秒标题循环，以及第一次下潜、地下水库、排水泵、撤离、死亡、胜利六段流程音乐。声音美术采用低频音床和稀疏和声音色；最终音乐节奏由游戏调度器控制。

## 复现与验证

需要 Python 3.12 标准库及 PATH 上的 FFmpeg/FFprobe；不安装 Python 包，也不在生成时下载素材。

```powershell
python tools/generate_audio_v2.py
python tools/check_audio_assets.py
```

交付格式统一 48 kHz：短音效单声道 WAV，环境与配乐立体声 Ogg Vorbis。循环处理在末尾短窗衔接到开头波形，保持环绕能量；不依靠首尾同时静音。检查报告写入不入库的 `artifacts/audio-assets-report.json`，包含每个成品的采样率、声道、解码后长度、循环接缝、RMS 和 FFmpeg 4 倍重建峰值。自动检查无法替代耳机与扬声器的实机试听。
