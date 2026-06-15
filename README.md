# PVE LXC 模板自动构建器

使用 GitHub Actions 手动构建 Proxmox VE LXC `tar.gz` 模板，并自动发布到 GitHub Releases。

## 已实现功能

- 仅手动触发 `workflow_dispatch`。
- 可选择单个系统版本，或者一次构建全部版本。
- 支持 `amd64`、`arm64` 或双架构。
- 支持 `minimal`、`standard`、`full` 三种软件包档位。
- 支持中科大 USTC、清华 TUNA、阿里云镜像。
- 删除原软件源配置，不创建 `.bak` 备份。
- 开启 SSH root 登录；模板内不预置通用 root 密码，由 PVE 创建 CT 时设置。
- 禁用 IPv4 DHCP、DHCPv6 和 IPv6 SLAAC。
- 每次开机在网络启动前重新检查并改写动态网络配置。
- 首次启动生成独立 `machine-id` 和 SSH Host Key。
- 清理内核、模块目录、引导文件、设备节点、缓存、日志及宿主机身份信息。
- 生成软件包清单、JSON manifest、SHA-256 和 SHA-512 校验值。
- 所有选中模板构建成功后，自动创建或更新 GitHub Release。

## 支持的系统

- Debian 12、13
- Ubuntu 22.04 LTS、24.04 LTS、26.04 LTS
- AlmaLinux 8、9、10
- Rocky Linux 8、9、10
- CentOS Stream 9、10
- Alpine Linux 3.21、3.22、3.23、3.24

Alpine 会自动寻找所选大版本分支中最新的补丁版本，例如 `3.24.1`。

## GitHub 上使用

1. 将本仓库推送到 GitHub。
2. 确保 `.github/workflows/build-release.yml` 位于默认分支。
3. 打开仓库的 **Actions** 页面。
4. 选择 **Build and release PVE LXC templates**。
5. 点击 **Run workflow**。
6. 选择系统、架构、软件档位、国内源和 Release Tag。
7. 构建完成后从仓库的 **Releases** 页面下载。

`release_tag` 填 `auto` 时会自动生成，例如：

```text
pve-lxc-2026.06.15-153000
```

## 软件包档位

### minimal

SSH、sudo、CA 证书、curl、wget、编辑器、基础网络诊断、压缩工具、时区和发行版正常联网所需组件。

### standard

在 minimal 基础上增加 Python、pip、Git、编译器、CMake、Ninja、调试工具、网络排障和常用命令行程序。

### full

在 standard 基础上尽量增加 Node.js、Java、Go、Rust、Ruby、PHP、数据库客户端、Redis、Nginx、FFmpeg、ImageMagick、Ansible 和常用开发头文件。

不同发行版中不存在的软件包会在整组安装失败后逐个重试；不可用的可选软件包会记录警告并跳过。minimal 包组属于强制依赖，安装失败会停止构建。

## 动态网络禁用方式

模板安装 `/usr/local/sbin/pve-static-only`，并在每次启动网络前执行。它会处理：

- `/etc/network/interfaces` 和 `interfaces.d`
- systemd-networkd `.network`
- Netplan YAML
- NetworkManager `.nmconnection`
- RHEL 系 `ifcfg-*`

处理规则包括：

- `inet dhcp` 改成 `manual`
- IPv6 `dhcp` 或 `auto` 改成 `manual`
- `DHCP=yes` 改成 `DHCP=no`
- `dhcp4: true`、`dhcp6: true`、`accept-ra: true` 改成 `false`
- NetworkManager `method=auto/dhcp` 改成 `disabled`
- `BOOTPROTO=dhcp` 改成 `none`
- sysctl 禁用 IPv6 RA 和 SLAAC

PVE 写入的静态 IPv4/IPv6 配置会保留。

这是模板内部限制。容器 root 用户拥有完全权限，仍可主动删除服务或修改规则。

## 首次启动初始化

首次启动服务执行一次：

- 生成独立 `/etc/machine-id`
- 创建 SSH Host Key
- 修正密钥权限
- 创建 `/var/lib/pve-template/initialized` 标记

构建模板时会删除该标记、SSH Host Key、machine-id 和随机种子，避免多个 CT 复用身份。

## 本地构建

推荐 Ubuntu 24.04：

```bash
sudo apt-get update
sudo apt-get install -y \
  acl attr ca-certificates curl debootstrap dnf file gawk git gnupg gzip jq \
  qemu-user-static binfmt-support rpm tar util-linux xz-utils zstd

sudo ./bin/build.sh \
  --target debian-13 \
  --arch amd64 \
  --profile full \
  --mirror ustc \
  --output ./dist
```

查看全部目标 ID：

```bash
./bin/list-targets.sh
```

运行静态检查：

```bash
./tests/static.sh
```

## 导入 PVE

在 PVE Web 后台进入：

```text
Datacenter → 节点 → local 存储 → CT Templates → Upload
```

上传生成的 `.tar.gz`，创建 CT 时设置 root 密码或 SSH 公钥，并填写静态 IPv4/IPv6。

## ARM64 说明

GitHub 的 x86-64 Runner 使用 `qemu-aarch64-static` 交叉构建 ARM64，因此明显慢于 amd64。选择全部系统和双架构会生成 34 个矩阵任务，可能消耗大量 Actions 分钟。

## RHEL 系首次引导说明

空 rootfs 尚无发行版签名密钥，因此首次最小化引导使用发行版官方 HTTPS 仓库并仅对第一次事务使用 `--nogpgcheck`。安装 release 包后导入发行版 GPG 密钥，再使用所选国内源和 `gpgcheck=1` 安装其余软件。

## 输出文件

```text
debian-13-pve-lxc-full-amd64.tar.gz
debian-13-pve-lxc-full-amd64.manifest.json
debian-13-pve-lxc-full-amd64.packages.txt
debian-13-pve-lxc-full-amd64.sha256
debian-13-pve-lxc-full-amd64.sha512
```

Release 还会额外生成汇总的 `SHA256SUMS` 和 `SHA512SUMS`。

GitHub Release 单文件限制为 2 GiB，打包脚本会在上传前检查并阻止超限模板发布。
