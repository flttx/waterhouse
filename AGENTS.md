# 深渊水房项目约束

## Never

- 不在未持有 `AudioServer.lock()` 的情况下调用 `AudioServer.set_bus_send()`。运行时路由统一通过 `WaterhouseSoundscape._send()`，跳过同目标重复写入；初始化音乐总线也必须配对 lock/unlock。Godot 4.7.2 的无锁 `StringName` 赋值已在真实 WASAPI 混音线程重复触发 `0xc0000005` / `0x31d6c57`，最小复现与加锁对照已确认。后续修改需运行 `tests/audio_routing_test.gd` 及完整通关回归，不能通过关闭音频或忽略进程失败绕过验证。
