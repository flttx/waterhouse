extends SceneTree
## Export the engine's own license metadata and offline controls with the binary.


func _initialize() -> void:
	var controls := FileAccess.open("res://build/PLAY.txt", FileAccess.WRITE)
	var licenses := FileAccess.open("res://build/GODOT_LICENSES.txt", FileAccess.WRITE)
	var audio_credits := FileAccess.open("res://build/AUDIO_CREDITS.txt", FileAccess.WRITE)
	if controls == null or licenses == null or audio_credits == null:
		push_error("Could not write Windows package metadata")
		quit(1)
		return
	controls.store_string("深渊水房 / The Waterhouse · 设施探索版\n\n双击 TheWaterhouse.exe，保留同目录 TheWaterhouse.pck。无需安装Godot或联网，建议佩戴耳机。\n\n约308×168米设施、19区域、16梯、8种生物（9个实例）。\nWASD移动；鼠标观察；Shift快跑/快游；按住C/Ctrl蹲伏/下潜；Space跳跃/上浮。\n按住E操作设备；水面近梯按E上岸；F手电；Q金属诱饵；Esc暂停/设置。\nM打开/关闭设施全图（浏览暂停）；+/-缩放探索小地图。\n\n标题选择难度：探索/求生/深渊。呼吸100/60/45秒，诱饵5/3/2枚，怪物感知/速度/伤害/前摇相应改变，三档均有完整AI。\n探索：实时小地图、实际路线和怪物位置/高差。求生：下一方向与下潜/上浮/爬岸/呼吸提示。深渊：关闭目标导航。\n\n十设备逃生：配电→主池两阀→西档案安全联锁→东过滤池调压→阶梯浴场/北溢流池/黑水地下库三阀→西泵房排水→等待85秒压力→开北闸门→步行穿过撤离通道。\n浮出水面恢复呼吸。灯光/声音会暴露位置，可利用遮挡、慢速移动和诱饵。\n死亡可重开。难度在新局开始时应用，设置保存在用户目录。\n\n这是已通过原生机制/静态通关验收的探索版；真人通关时间与九怪物合并平衡仍需体验调优。\n引擎：Godot %s / Windows x64 / OpenGL Compatibility。\n" % Engine.get_version_info()["string"])
	controls.store_string("\n声音版本 0.3：Esc设置中可分别调总音量、音效、环境和音乐；所有音量可完全静音。\n六组空间环境、水上/水下与障碍遮挡混音、八类生物预兆及命中声音、随危险和逃生进度变化的克制配乐。地图/暂停冻结世界声音和配乐，保留菜单反馈。\n本包AUDIO_CREDITS.txt包含免费录音作者、来源、许可证与加工说明。声音机制已自动验证；完整耳机/扬声器试听和恐怖节奏仍需要玩家体验。\n")
	controls.close()
	audio_credits.store_string(FileAccess.get_file_as_string("res://assets/audio/AUDIO_SOURCES.md"))
	audio_credits.store_string("\n\nWater splashes attribution and license notice\n\n" + FileAccess.get_file_as_string("res://assets/audio/v2/source/WATER_LICENSE.txt"))
	audio_credits.close()
	licenses.store_string("Godot Engine license\n\n" + Engine.get_license_text())
	licenses.store_string("\n\nEngine third-party copyright information\n\n" + JSON.stringify(Engine.get_copyright_info(), "\t"))
	licenses.store_string("\n\nEngine third-party license texts\n\n" + JSON.stringify(Engine.get_license_info(), "\t"))
	licenses.close()
	print("PASS exported native license metadata and offline controls")
	quit()
