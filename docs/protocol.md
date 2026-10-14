# AM Infinity .97：独立互操作协议笔记

来源：2026-10-14 读取官方公开页面 `https://ammaster.angrymiao.com/mouse` 的 `assets/index-32dd77b9.js`，对照本机 I/O Registry 描述符与实际收发结果。这里只记录互操作事实；源码为独立 Swift 实现，未嵌入官方 JS、Python 或固件。界面展示素材归属见 THIRD_PARTY_NOTICES.md。

## 实机接口

- VID `3725 / 0x0e8d`；接收器 PID `1795 / 0x0703`。
- 配置集合 Usage Page `0xff13`，Feature Report `0x14`。
- 包含 Report ID 的报告长度 62 字节：`14 | size | route | RACE bytes | zero padding`。
- 2.4G 鼠标路由 `0x80`；`0x00` 是接收器本地路由。
- 实测直接使用 `0x80` 读取成功，没有更改配对、link type 或固件。
- USB 本体 PID `2176 / 0x0880`、路由 `0x00` 来自官方脚本，尚未在本 App 实测。

## 报文

RACE 请求：`05 5a <payloadLength+2, LE16> <command, LE16> <payload>`。

回复观察到 `05 5b` 和 `05 5d`，其后同样为长度、命令、负载。成功负载首字节为 `00`。回复可能分片或混有通知，因此按路由过滤并重组、校验命令、长度与状态。不要只看到 USB 调用成功便认为硬件已应用。

| 命令 | 含义 | 参数 |
|---|---|---|
| `0x30c5` | 读 DPI | 无 |
| `0x30cf` | 读鼠标电量 | 无 |
| `0x30c9` | 读当前配置 | 无 |
| `0x30c4` | 写一档 DPI | 档位 index u8 + X LE16 + Y LE16 |
| `0x30c7` | 选择/刷新当前 DPI 档位 | index u8 |

实测 DPI 负载 35 字节：status、有效档数、当前 index、8 个 X LE16、8 个 Y LE16。写 DPI 不携带 RGB，因此不改灯光。若修改当前档位，按官方行为再发当前 index 使其生效；本轮物理写入验证仅覆盖非当前档位，当前档位刷新分支尚未实测。

实测电量回复：`00 00 43 ff 01 22 01`，第三字节 `0x43=67%`，第二字节未充电。短格式只读取 16 位百分比，充电状态未知；不把未知当作已证实状态。

## 边界

未探测未知写命令、未刷固件、未恢复出厂、未修改板载其他配置。没有解决所有固件/连接版本差异。现有设备断开或休眠超时会显式报错；不能保证所有固件支持该路由。

## 0.3.0 按键与版本查询

2026-10-14 对照同一官方公开客户端并实机确认：

| 命令 | 含义 | 参数 |
|---|---|---|
| `0x30c3` | 读取按键映射 | physical key ID u8 |
| `0x30c2` | 写入按键映射 | key ID + type + params |
| `0x1c07` | 固件版本（只读） | `00`；鼠标 route 0x80，接收器 route 0x00 |

映射回复为 status + key ID + type + params。1–7 分别为左、右、中、前侧、后侧、上滚、下滚。默认 type 为 1、2、3、4、5、12、13，参数为空。type 6 为快捷键：consumer usage LE16 + keyboard usage u8 + modifiers u8；修饰位 Ctrl=1、Shift=2、Alt=4、Command=8。后侧键 Cmd+C 实测写入 `[5,6,0,0,6,8]` 并读回。未知类型/宏按字节保留，不编辑宏；超过当前单包安全恢复长度的映射拒绝修改。

每次写入先读取全部 7 键及配置，检查草稿基线一致，原始事务原子落盘并同步，再只写目标键；读回全部映射必须精确一致。异常尝试恢复；未确认时保留 pending。至少保留一个左键。恢复限制同一个 HID 连接实例和板载配置，避免误写其他鼠标。

版本查询可能先返回单字节成功 ACK，随后才返回版本；ACK 不能当成完整版本。实测两端回复 `[0,0,6,118,49,46,56,46,52]`，ASCII 为 `v1.8.4`。

## 官方更新来源

- Mac 驱动：GET `https://diy.angrymiao.com/api/version-manager/history-version?app_code=AM_Master&platform=mac`，按数字版本排序取最新。
- 固件：POST `https://diy.angrymiao.com/api/firmware/check`，型号 AM_35_MOUSE / AM_35_DONGLE。
- 固件接口的公开客户端 selector 从官方鼠标页加载的 index JS 在内存中解析；不执行、不落盘脚本或 selector，不发送设备序列号。页面结构变化明确报错。
- HTTPS 官方域名校验、超时、响应格式及版本校验；不下载响应中链接的固件/驱动，不执行升级。
- 查询快照（2026-10-14）：固件 1.8.4，官方 Mac 驱动 V1.3.9。本机 AM_Master 的 bundle 版本为无效占位值 0.0.0，不能声称已安装最新驱动。
