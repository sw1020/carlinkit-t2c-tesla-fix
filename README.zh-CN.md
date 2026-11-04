# CarlinKit T2C 特斯拉浏览器分辨率修复

[English](README.md) | 中文

特斯拉车机浏览器更新后，通过 CarlinKit T2C 使用 CarPlay 时画面会被裁切或缩放不对。这个项目提供一套可复现、可审查的构建流程：从官方地址下载固件，打上两个前端补丁，重新打包成可刷入的固件。

本仓库 fork 自 [randolfrias/carlinkit-t2c-tesla-fix](https://github.com/randolfrias/carlinkit-t2c-tesla-fix)，修复了新版 squashfs-tools 下非 root 用户构建失败的问题（见下文"与上游的差异"）。

## 问题原因

T2C 固件的网页界面里有这样一条样式：

```css
body {
    min-width: 1024px;
}
```

新版特斯拉浏览器的可视宽度大约只有 `773px`，但因为这条规则，页面拿到的 `window.innerWidth` 变成了 `1024px`。T2C 建立 WebSocket 连接时会把 `innerWidth` / `innerHeight` 发给后端，于是 CarPlay 画面比浏览器实际可见区域更大，右边和下边被裁掉。

补丁只改两处：

1. `min-width: 1024px` 改成 `min-width: 0`。
2. `setTimeout(rf(), 1000)` 改成 `setTimeout(rf, 1000)`。原写法会立即执行回调，而不是延迟 1 秒执行。

## 适用环境

| 项目 | 值 |
| --- | --- |
| 转接盒 | CarlinKit T2C |
| 固件分支 | `1508` |
| 已测试固件版本 | `26020416.1508.1` |
| 项目名 | `ly1508` |
| 系统平台 | 全志 Tina Linux |
| 特斯拉浏览器视口 | `773 x 601` |
| 上游测试车辆 | Tesla Model Y 2023 |
| 本 fork 维护者车辆 | Tesla Model Y 2022 |

构建环境：macOS（Apple Silicon，Homebrew）。

## 风险提示

**刷机有变砖风险。** 镜像有问题、硬件版本不匹配、升级中途断电，或者 recovery 流程出现意外，都可能让转接盒无法启动。

- 不要把生成的固件刷到其他固件分支或其他硬件版本上。
- 官方公布的固件版本和已测试版本不一致时，脚本会主动停止，除非你显式加上 `FORCE=1`。
- 升级流程会重写 `boot`（内核）和 `customer`（应用）两个分区，**没有 A/B 自动回滚**。网页升级页面也在 `customer` 分区里，一旦它损坏，可能就无法再通过网页刷回官方固件。
- 刷机前请确认能打开网页升级页面，并在本地留一份官方 `update.img`。

## 为什么只提供构建脚本，不直接发布固件

- 固件主体是厂商的闭源程序，版权不属于本项目，不适合二次分发。
- 每次构建出来的 MD5 都不一样（文件时间戳会变），别人拿到成品镜像无法自行验证，只能选择信任。
- 自己构建可以看清楚到底改了什么，固件也是自己从官方地址下载的。

所以请**自己运行脚本构建**，不要使用来源不明的成品镜像，也不要把自己构建的镜像发给别人。

## 环境准备（macOS）

如果还没装 Homebrew：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

安装依赖：

```bash
brew install python cpio squashfs binwalk
brew install nmap   # 可选，排查网络问题时有用
```

Apple Silicon 机型：

```bash
export PATH="/opt/homebrew/bin:$PATH"
export PATH="/opt/homebrew/opt/cpio/bin:$PATH"
```

确认安装的是 GNU cpio：

```bash
/opt/homebrew/opt/cpio/bin/cpio --version
```

不需要 root 权限，也不要用 `sudo` 运行脚本。

## 1. 检查设备固件版本

电脑连上 T2C 的 Wi-Fi，运行：

```bash
./scripts/check-device.sh
```

脚本只输出判断兼容性需要的固件信息，不会输出序列号、MAC 地址等标识。

应该看到：

```text
26020416.1508.1
```

如果版本或分支不一致，除非你清楚自己在做什么，否则请停下来。

## 2. 构建

```bash
./scripts/build.sh
```

脚本会依次完成：

1. 下载 `1508` 分支的 `version.json`。
2. 确认官方公布的版本和已测试版本一致。
3. 下载官方 `update.img`。
4. 校验外层 MD5。
5. 解出 `update.swu`，再解开其中的 CPIO 包。
6. 确认 `sw-description` 里的项目名是 `ly1508`。
7. 解开 `customer` SquashFS 文件系统。
8. 应用 `patches/` 目录下的两个补丁，并检查补丁确实生效。
9. 按官方原有参数重新打包 `customer`（xz 压缩，256K 块）。
10. 重新生成 CRC 格式的 CPIO `update.swu`，并加上外层 MD5。
11. 自动校验最终镜像。

生成的文件：

```text
build/T2C-custom-update.img
```

官方版本号变了但你确认仍然兼容，可以强制构建：

```bash
FORCE=1 ./scripts/build.sh
```

## 3. 校验

可以单独再跑一次校验：

```bash
./scripts/verify.sh build/T2C-custom-update.img
```

校验内容：

- 外层 MD5 与内部 SWU 一致；
- CPIO 使用 CRC 格式（`070702`）；
- `sw-description`、`customer`、`kernel` 三个文件都在；
- 项目名是 `ly1508`；
- 最终镜像里有修改后的 CSS 和 JS；
- `dev/console` 设备节点存在；
- 输出 `customer` 的 SHA-256 便于记录。

## 4. 刷机

连上 T2C 的 Wi-Fi，**确保供电稳定**。建议在家用稳定电源操作，不要在车上一边开一边刷。

```bash
curl -v \
  -F 'file=@build/T2C-custom-update.img;filename=update.img' \
  'http://192.168.3.1/cgi-bin/index.cgi?id=upload'
```

正常返回：

```json
{"code": 0, "msg": "upload successful"}
```

上传完成后**不要断电**。设备会在 recovery 流程中重启一到多次。

## 5. 确认补丁生效

等 T2C 的 Wi-Fi 重新出现后：

```bash
curl -s 'http://192.168.3.1/cgi-bin/index.cgi?id=host'
```

先打开网页升级页面，确认还能用（以后需要时还能刷回官方固件）。

然后在 Chrome 里打开 T2C 页面，用开发者工具把视口设成 `773 x 601`，在控制台运行：

```javascript
({
  innerWidth: window.innerWidth,
  innerHeight: window.innerHeight,
  bodyWidth: document.body.getBoundingClientRect().width,
  documentWidth: document.documentElement.getBoundingClientRect().width
})
```

补丁生效后应该是：

```text
innerWidth:    773
innerHeight:   601
bodyWidth:     773
documentWidth: 773
```

最后再到车上实际测试 CarPlay 画面。

## 恢复官方固件

- **网页升级页面还能打开**：用上面同样的 `curl` 命令上传官方 `update.img` 即可。
- **网页打不开**：`recovery` 分区在升级时不会被改写，但目前没有确认设备是否支持 U 盘或按键触发升级。
- **完全无法启动**：全志平台理论上可以进入 FEL 模式用 USB 线刷（`sunxi-fel` / PhoenixSuit），但通常需要拆壳，还需要完整的线刷包，官方并没有公开，难度很大。

## 与上游的差异

squashfs-tools 4.6 及以后的版本中，非 root 用户运行 `unsquashfs` 遇到无法创建的设备节点（固件里的 `dev/console`）时，会以非 0 状态退出，导致构建中断：

```text
create_inode: could not create character device squashfs-root/dev/console, because you're not superuser!
```

本 fork 的处理：

- 解包时排除 `dev/console`，打包时通过 `mksquashfs` 的 pseudo 定义（`dev/console c 600 0 0 5 1`）原样加回去；
- 解包时使用 `umask 0000`，保留原有文件权限（例如 `eyesee-mpp/*.so` 的组写权限）；
- 删除 `patch` 产生的 `.orig` 备份文件，避免被打进固件；
- `verify.sh` 增加 `dev/console` 设备节点检查。

修改后，重新打包的 `customer` 与官方原版相比，文件列表、权限、属主、设备节点都一致，只有补丁涉及的文件内容不同。

## 升级流程说明

官方固件使用 SWUpdate，大致流程：

```text
update.img
  -> 校验并解出 update.swu
  -> upgrade_recovery
  -> swu_mode=upgrade_kernel, ly_boot_mode=update, boot_partition=recovery
  -> 重启进入 recovery
  -> 写入 kernel + customer
  -> upgrade_usr
  -> boot_partition=boot, ly_boot_mode=normal
  -> 重启
```

写入的分区：

```text
kernel   -> /dev/by-name/boot
customer -> /dev/by-name/customer
```

## 隐私

分享日志或截图时，请不要公开：

- 序列号、UUID；
- Wi-Fi / 蓝牙 MAC 地址；
- IMEI；
- 终端提示符里的个人用户名；
- 其他能识别具体设备的信息。

## 许可与免责

本仓库中的脚本、补丁和文档使用 MIT 许可证。构建过程中下载的 CarlinKit 官方固件属于厂商的专有软件，不在 MIT 许可范围内，适用其所有者的条款。

使用风险自负。本项目仅用于技术研究和可复现构建，与 CarlinKit、特斯拉、苹果公司均无关联，也未获得它们的认可。
