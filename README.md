
---

# 📘 **README.md — AlmaLinux Ultra Bootstrap**

## 🚀 项目简介

`init_alma_ultra_full.sh` 是一份 **面向 RackNerd / HostHatch / 美国便宜 VPS** 的“一键开荒脚本”，目标是：

* 在 **重装系统后 5–10 分钟** 将 VPS 带到可用状态
* 涵盖：系统配置、安全、SSH、监控、Docker、zsh、美化、开发环境等
* 可作为你的 **个人服务器标准镜像初始化模版**

适用于：

* 写作（Doom Emacs / Neovim）
* 部署轻量服务（n8n、Caddy、Web 应用）
* Tailscale 内网管理
* 个人代理节点（Hysteria2、NaïveProxy）
* 各种自动化任务

---

# ⚙️ **运行环境与前提**

* 仅面向 **AlmaLinux / RHEL 系发行版** 设计：  
  脚本会读取 `/etc/os-release`，若 `ID != almalinux` 会给出警告，需要你确认是否继续。
* 依赖 `dnf` 或 `yum`：  
  若系统中不存在 `dnf/yum`，脚本会直接退出，避免在 Debian/Ubuntu 上误操作。
* 需以 **root 身份** 运行（例如：`sudo -i` 后执行脚本）。
* 脚本运行时会自动生成日志文件到 `/var/log/vps_init_YYYYMMDD_HHMMSS.log`，方便后续排查问题。
* 脚本会在开始时检查网络连接，确保后续安装步骤能正常进行。
* 强烈建议在运行脚本前先配置好 **SSH 免密登录**（`ssh-copy-id`），并在确认公钥登录正常后再禁用密码登录 / 修改端口。
* 推荐在一台 **干净的 AlmaLinux 系统** 上使用本脚本。如果系统曾手工编译/安装过自带的 `sshd`，可能会遇到类似 `OpenSSL version mismatch` 的问题，此时应先通过 `dnf reinstall openssh-server` 等方式恢复系统自带的 OpenSSH。

# 🚀 **快速上手指南（推荐流程）**

## 1️⃣ 上传脚本并赋权

在本地终端（假设远程 root 已可用）：

```bash
scp init_alma_ultra_full.sh root@YOUR_IP:/root/
ssh root@YOUR_IP
chmod +x /root/init_alma_ultra_full.sh
```

## 2️⃣ 以 root 执行脚本

```bash
cd /root
./init_alma_ultra_full.sh
```

首次运行时脚本会一路问你一系列问题，你可以按提示直接回车使用默认值，或参考下面的推荐选项。  
之后再次运行脚本时，会自动读取上一次的配置（保存在 `/root/.alma_vps_init.conf`），你只需在“是否直接使用上述配置并跳过参数输入？[Y/n]”那里回车即可快速带过所有参数。

## 3️⃣ 交互问题参考答案（个人常用）

- 主机名：`alma-vps` 或类似有含义的名字
- 普通用户名：`noah` 或你自己的常用用户名
- SSH 端口：`2222`（推荐），后续搭配“关闭 22 端口”
- 是否在防火墙中关闭默认 SSH 端口 22：**y**（确认新端口可用后就可以只保留新端口）
- 是否关闭 ping：个人 VPS 通常选 **y**（需要被 ping 时再改）
- 是否启用 BBR：**y**（脚本会顺带检查内核是否支持 BBR）
- 是否禁用 SELinux：看个人偏好；便宜 VPS 上一般选 **y**，然后重启
- 是否安装 Tailscale：**y**（用于内网访问和管理）
- 是否安装 Docker：**y**（后续跑 n8n / 自建服务都方便）
- 是否准备 Doom Emacs 环境：按需（写作/开发用 Emacs 就选 **y**）
- 是否安装监控栈（Netdata / vnstat / btop / glances / ncdu / fail2ban）：推荐 **y**
- 是否安装 Caddy：如果有 Web/反代需求就选 **y**
- 是否将 Netdata Web 端口 19999 对公网开放：一般选 **n**，通过 Tailscale 或反代访问更安全

## 4️⃣ 脚本执行完成后的常用动作速查

- 用新端口测试 SSH 登录：

  ```bash
  ssh -p 2222 NEW_USER@SERVER_IP
  ```

- 上传 SSH 公钥，并关闭密码登录：

  ```bash
  ssh-copy-id -p 2222 NEW_USER@SERVER_IP
  # 登录上去后：
  sudo vim /etc/ssh/sshd_config   # 改为 PasswordAuthentication no
  sudo systemctl restart sshd
  ```

- 在新用户下启动 Tailscale（如果安装了）：

  ```bash
  su - NEW_USER
  sudo tailscale up
  ```

- 测试 Docker（如果安装了）：

  ```bash
  su - NEW_USER
  docker run --rm hello-world
  ```

- 安装 Doom Emacs（如果准备了环境）：

  ```bash
  su - NEW_USER
  ./install_doom.sh
  ```

- 访问 Netdata（推荐走 Tailscale）：

  ```text
  http://<tailscale-ip>:19999
  ```

- 最后重启一次，让 SELinux / BBR / sysctl 等设置彻底生效：

  ```bash
  reboot
  ```

# ✔️ **脚本自动完成的内容**

脚本会自动完成以下所有配置：

## 🧱 1. 系统基础与安全

* 日志记录：所有脚本输出自动保存到 `/var/log/vps_init_*.log`
* 网络检查：开始前检查网络连接，避免安装失败
* 更新系统、清理缓存（如遇依赖冲突，会自动尝试 `--skip-broken` 继续；若仍失败，脚本会提示你手动使用 `dnf -y update --allowerasing` 排查）
* 设置主机名（带基础合法性校验，仅允许字母 / 数字 / 点 / 连字符）
* 防火墙（firewalld：开放自定义 SSH 端口，可选关闭默认 22 端口，按需开放 Netdata 19999 / Caddy 80、443）
* SSH 加固（端口替换、禁用 root 登录，保留密码登录以便首登；修改 `sshd_config` 前会自动备份为 `sshd_config.vps-init.bak`，并在重启前用 `sshd -t` 做语法检查，如有错误会提示你手动修复而不会强制重启 sshd）
* 可选关闭 ping
* 可选启用 BBR（使用官方推荐的 `fq` qdisc，附带内核支持检测：若内核未暴露 `bbr`，会给出提示）
* 可选禁用 SELinux（需重启）；如不禁用且 SELinux 为 Enforcing/Permissive，会自动尝试用 `semanage port` 放行新的 SSH 端口

## 👤 2. 用户与权限

* 自动创建一个普通用户（用户名带合法性校验）
* 添加到 wheel（sudo）组
* 设置密码（仅在首次创建用户时要求设置，避免重复运行时重复输入）
* 如 root 已配置 `~/.ssh/authorized_keys`，会自动为新用户创建 `~/.ssh/authorized_keys` 并同步相同公钥，支持多次运行时自动去重，避免重复添加相同公钥（之后你可以再用 `ssh-copy-id` 为新用户追加自己的其他公钥）

## 🧵 3. Shell + 美化环境

* zsh
* oh-my-zsh
* z.lua
* zsh-autosuggestions
* zsh-syntax-highlighting
* powerlevel10k
* 自动生成配置文件（包含插件与主题）
* 使用 `command -v zsh` 自动检测 zsh 路径，并将新用户默认 shell 切换为系统上的 zsh（例如 `/usr/bin/zsh`）

## 🛠 4. 开发工具

* git / curl / wget
* fzf / ripgrep
* tmux
* vim / neovim
* gcc / make / build-essentials

## 🖥 5. Emacs (Doom Emacs)

* 自动 clone DoomEmacs 仓库
* 自动生成 `install_doom.sh` 一键部署脚本（内部会在安装前自动将已有的 `~/.emacs` 备份为 `~/.emacs.pre-doom.bak`，避免与 Doom 配置冲突）

### 🔧 手动安装新版 Emacs（用于 Doom 排错，可选）

有时候 Doom 没有正常启动，你可能会怀疑是 VPS 自带 Emacs 版本过低导致的（如 AlmaLinux 默认的 `emacs-27.2`）。  
虽然 Doom 官方要求的最低版本通常是 27.1，但为了彻底排除“版本问题”，可以在 **用户目录中手动编译一个最新版 Emacs**，不动系统自带版本。

思路：

* 保留系统自带 `emacs-27.x` 作为默认包管理版本；
* 在 `$HOME` 下用源码编译一个 `emacs-29/30`，安装到 `~/.local`；
* 通过 `PATH` 或环境变量 `EMACS` 让 Doom 使用新版本。

#### 1️⃣ 安装编译依赖（需要 root / sudo）

```bash
sudo dnf groupinstall "Development Tools"

sudo dnf install \
  gcc make autoconf automake texinfo \
  ncurses-devel gnutls-devel \
  libjpeg-turbo-devel libpng-devel giflib-devel \
  libXpm-devel libX11-devel libXau-devel libXdmcp-devel \
  libselinux-devel
```

如果只打算在终端里用（`emacs -nw`），上面一套依赖已经足够通用，不需要额外 GUI 包。

#### 2️⃣ 下载并编译 Emacs（示例：29.3）

可以在 `~/src` 下面放源码（方便以后重编）：

```bash
mkdir -p ~/src && cd ~/src

# 到 GNU 官网查看当前最新版本，把 29.3 换成实际版本号
curl -LO https://ftp.gnu.org/gnu/emacs/emacs-29.3.tar.xz
tar xf emacs-29.3.tar.xz
cd emacs-29.3

# 只编译终端版，安装到 ~/.local
./configure --prefix="$HOME/.local" --without-x --without-sound --without-pop

make -j"$(nproc)"
make install
```

完成后，新的 Emacs 会在 `~/.local/bin/emacs`。

#### 3️⃣ 让 Shell 使用新 Emacs

优先方法：把 `~/.local/bin` 放到 `PATH` 前面（以 zsh 为例）：

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

emacs --version   # 应该显示 29.x 或你编译的版本
```

如果不想改全局 `PATH`，也可以按命令临时指定：

```bash
$HOME/.local/bin/emacs --version
```

#### 4️⃣ 让 Doom 使用这个 Emacs

Doom 会优先使用环境变量 `EMACS` 指定的 Emacs 路径，然后才会用 `PATH` 中的 `emacs`。  
因此可以在排错时显式指定：

```bash
# 用新 Emacs 运行 Doom 相关命令
EMACS="$HOME/.local/bin/emacs" ~/.emacs.d/bin/doom doctor
EMACS="$HOME/.local/bin/emacs" ~/.emacs.d/bin/doom sync
EMACS="$HOME/.local/bin/emacs" ~/.emacs.d/bin/doom env

# 启动 Doom Emacs
EMACS="$HOME/.local/bin/emacs" ~/.emacs.d/bin/doom run
# 或直接
EMACS="$HOME/.local/bin/emacs" emacs
```

如果这样能正常启动 Doom，而用系统自带 `emacs-27.2` 不能，就可以确认问题确实与 Emacs 版本有关；  
后续可以考虑在初始化脚本中集成“可选编译新版 Emacs”流程。

## 🧵 6. 监控工具栈（可选）

包含：

| 工具           | 用途                |
| ------------ | ----------------- |
| **Netdata**  | Web UI 实时监控       |
| **vnstat**   | 流量计量（RackNerd 必备） |
| **btop**     | 高级系统监控            |
| **glances**  | 全局资源查看            |
| **ncdu**     | 磁盘占用分析            |
| **fail2ban** | 防 SSH 爆破          |

Netdata 将监听 `19999` 端口：  
* 默认 **不对公网开放**，推荐通过 **Tailscale / 内网 / 反代** 访问；  
* 脚本中提供选项，可一键在 firewalld 中开放 `19999/tcp`。

监控相关工具的常用命令速查：

- `vnstat`：查看流量统计（先用 `vnstat --iflist` 查网卡名）
  - 按天：`vnstat -i <网卡> -d`
  - 按月：`vnstat -i <网卡> -m`
  - 按小时：`vnstat -i <网卡> -h`
- `fail2ban`：查看和管理 SSH 暴破封禁
  - 总览：`sudo fail2ban-client status`
  - 只看 sshd：`sudo fail2ban-client status sshd`
  - 解封 IP：`sudo fail2ban-client set sshd unbanip 1.2.3.4`
- `netdata`：Web 实时监控（Agent 本地界面）
  - 服务状态：`sudo systemctl status netdata`
  - 启动/开机自启：`sudo systemctl enable --now netdata`
  - 端口检查：`sudo ss -tlnp | grep netdata`
  - 访问方式：
    - Tailscale：`http://<tailscale-ip>:19999`
    - SSH 转发：`ssh -L 19999:127.0.0.1:19999 user@server` 然后浏览器开 `http://127.0.0.1:19999`

## 🐳 7. Docker（可选）

* Docker CE
* Docker CLI
* containerd
* buildx
* compose-plugin
* 自动将用户加入 `docker` 组
* 开箱即用

## 🌐 8. Tailscale（可选）

* 一键安装
* 你只需执行：

```bash
sudo tailscale up
```

即可从本地访问 VPS 私有网络。

## 🌐 9. Caddy（可选）

* 自动安装
* 自动启用
* 自动在 firewalld 中开放 HTTP/HTTPS 服务（80/443）
* 自动生成示例 Caddyfile（反代模板）

---

# 🔮 **未来可扩展接口（建议加入但当前脚本未包含）**

下列是你未来随时可以“挂接”的模块接口，脚本中都预留了位置，不会对系统造成冲突。

## ① 数据库接口

支持未来加入：

### 1. **PostgreSQL（推荐）**

* 企业级稳定
* 可以用于 n8n、所有 Node 项目
* 安装模板：

```bash
dnf install -y postgresql-server postgresql-contrib
postgresql-setup --initdb
systemctl enable --now postgresql
```

### 2. **MariaDB / MySQL**

适用于传统应用：

```bash
dnf install -y mariadb-server
systemctl enable --now mariadb
```

### 3. **SQLite**

系统通常已自带，无需额外安装。

---

## ② Node.js 接口

适用于：

* n8n
* Astro、Next.js、SvelteKit
* 自己的前端工具链
* Cloudlfare Workers 本地开发

推荐使用 nvm：

```bash
su - USERNAME
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
nvm install --lts
```

---

## ③ n8n 自动化工作流接口

未来加入：

```bash
mkdir -p ~/apps/n8n
cat > ~/apps/n8n/docker-compose.yml <<EOF
version: '3'
services:
  n8n:
    image: n8nio/n8n
    container_name: n8n
    restart: unless-stopped
    ports:
      - 5678:5678
    volumes:
      - ./data:/home/node/.n8n
EOF

docker compose up -d
```

然后用 Caddy 提供 HTTPS。

---

## ④ NaïveProxy / Hysteria2 接口

例如可通过如下方式使用：

```bash
bash -c "$(curl -fsSL https://github.com/...)"
```

后续脚本可加入“一键部署代理节点”。

---

## ⑤ HTTPS / Domain 自动设置接口（Caddy）

未来脚本可加入 “自动绑定域名” 功能：

```bash
your.domain {
    reverse_proxy localhost:3000
}
```

Caddy 会自动生成 HTTPS，实现全自动证书续期。

---

## ⑥ Web App 部署接口

未来加入：

* Python (uv) 服务
* Flask / FastAPI
* Node.js 服务
* Hugo / 静态站点（可配合 Cloudflare Pages 等平台）

---

## ⑦ 持续备份接口

建议加入：

* Rclone → Google Drive / S3
* restic → 版本化备份
* 自动备份数据库 + docker 卷

---

# 📁 脚本结构概览（逻辑图）

```
init_alma_ultra_full.sh
├── 日志记录（自动保存到 /var/log/）
├── 基本检查（root 权限、系统类型、dnf/yum）
├── 网络连接检查
├── 配置文件加载/交互式参数确认
├── 系统配置
│   ├── 主机名
│   ├── 系统更新与基础软件
│   ├── SELinux
│   ├── sysctl 调优（ICMP / BBR）
│   └── Firewalld
├── 用户管理
│   ├── 创建普通用户
│   ├── 设置密码（仅首次）
│   ├── 加入 wheel 组
│   └── 同步 SSH 公钥（自动去重）
├── SSH 安全
│   ├── 端口替换
│   ├── 禁用 root 登录
│   ├── 配置备份与语法检查
│   └── SELinux 端口策略
├── Tailscale（可选）
├── Docker（可选）
├── 监控栈（可选）
│   ├── vnstat / glances / ncdu
│   ├── fail2ban
│   └── Netdata
├── Caddy（可选）
├── 用户目录结构准备
├── Shell 环境
│   ├── zsh
│   ├── oh-my-zsh
│   ├── zsh 插件（autosuggestions / syntax-highlighting）
│   ├── z.lua
│   └── powerlevel10k
├── Doom Emacs 环境准备（可选）
└── 收尾提示
```

---

# 🧩 **未来模块扩展模板**

你以后写自己的扩展脚本只需要：

```bash
# ===== Module: NAME =====

echo "[*] Installing NAME ..."
dnf install -y SOME_PACKAGE || true

# 可选的 systemctl
systemctl enable --now service_name || true

echo "[*] NAME installed."
```

模块复制后即可挂到主脚本尾部。

---

# 🔐 使用 Tailscale + iptables 限制 SSH 登录

## 背景：只允许 Tailscale 内网 SSH，屏蔽公网 IP

目标：
- 只允许通过 Tailscale 虚拟网卡（`tailscale0`）访问 SSH 端口。
- 所有来自真实公网 IP 的 SSH 连接一律拒绝（看起来像端口没开）。
- 其他服务端口（80/443 等）不受影响。

这里以 AlmaLinux 9 + SSH 端口 `2222` 为例，其他端口只需把 `2222` 替换为你的实际端口。

## 步骤 1：确认 SSH 端口

在 VPS 上：

```bash
sudo grep -E '^(Port|ListenAddress|AddressFamily)' /etc/ssh/sshd_config
```

确保：

```text
Port 2222
#AddressFamily any
#ListenAddress 0.0.0.0
#ListenAddress ::
```

也就是说：
- 只显式指定端口为 2222。
- 暂时不要写任何 `ListenAddress`，恢复为“监听所有地址”的默认行为。

修改后检查配置并重启：

```bash
sudo sshd -t              # 没输出 = 语法 OK
sudo systemctl restart sshd
ss -tulpn | grep 2222     # 确认 sshd 在 2222 监听
```

## 步骤 2：确认 Tailscale 工作正常

在 VPS 上：

```bash
tailscale ip -4
```

记住 VPS 自己的 Tailscale IP，例如：

```text
100.x.y.z
```

在本机（或其他 Tailscale 设备）上，用 Tailscale IP 测试 SSH：

```bash
ssh -p 2222 user@100.x.y.z
```

能登录说明 Tailscale 正常工作。

## 步骤 3：用 iptables 只允许从 tailscale0 访问 SSH

只在 **VPS 上** 执行下面命令（端口按需修改）：

```bash
sudo iptables -A INPUT -i tailscale0 -p tcp --dport 2222 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 2222 -j DROP
```

解释：
- 第 1 条：允许所有“从 `tailscale0` 网卡进来的、目标端口为 2222 的 TCP 流量”。
- 第 2 条：将其他所有“目标端口为 2222 的 TCP 流量”全部丢弃。

注意：这里检查的是 **进入 VPS 的接口（网卡）**，不是 VPS 自己的 IP。
- 通过 Tailscale IP 连上来的流量，会从 `tailscale0` 进入 → 匹配第 1 条 → 被允许。
- 通过公网真实 IP 连上的流量，会从 `eth0`/`ens…` 等物理网卡进入 → 不匹配第 1 条 → 落到第 2 条 → 被 `DROP`。

查看规则确认：

```bash
sudo iptables -L INPUT -n --line-numbers
```

示例输出（简化）：

```text
Chain INPUT (policy ACCEPT)
num  target   prot source      destination
1    ts-input all  0.0.0.0/0   0.0.0.0/0
2    ACCEPT   tcp  0.0.0.0/0   0.0.0.0/0   tcp dpt:2222  # 实际上只匹配 -i tailscale0
3    DROP     tcp  0.0.0.0/0   0.0.0.0/0   tcp dpt:2222
```

`iptables -L` 默认不显示接口，所以第 2 条看起来像“所有来源都 ACCEPT”，实际上带着 `-i tailscale0` 条件。

## 步骤 4：验证效果

1. 从 Tailscale 内的设备（例如本地电脑）：

   ```bash
   ssh -p 2222 user@100.x.y.z
   ```

   应该可以登录。

2. 从真实公网环境（例如手机 4G + VPS 公网 IP）：

   ```bash
   ssh -p 2222 user@<VPS 公网 IP>
   ```

   应该连接不上（超时 / 无响应）。

到这里为止：
- **所有真实世界公网 IP 直接访问 VPS:2222 都被屏蔽**。
- **只有通过 Tailscale（tailscale0）进来的 SSH 请求才被接受**。

## 步骤 5：让 iptables 规则在 AlmaLinux 9 中持久化

默认直接用 `iptables` 命令添加的规则是“临时的”，重启后会丢失。AlmaLinux 9 上可以手动保存并在开机时自动恢复：

### 5.1 保存当前规则

在 VPS 上：

```bash
sudo iptables-save | sudo tee /etc/sysconfig/iptables
```

### 5.2 创建 systemd 服务自动恢复规则

```bash
sudo tee /etc/systemd/system/iptables-restore.service >/dev/null << 'SERVICEEOF'
[Unit]
Description=Restore iptables firewall rules
After=network.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/iptables-restore /etc/sysconfig/iptables
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICEEOF

sudo systemctl daemon-reload
sudo systemctl enable --now iptables-restore.service
```

验证服务是否能正确恢复规则：

```bash
sudo iptables -F INPUT
sudo systemctl restart iptables-restore.service
sudo iptables -L INPUT -n --line-numbers
```

如果看到之前的第 2 条 `ACCEPT` 和第 3 条 `DROP` 规则都回来了，说明持久化生效。

### 5.3 以后修改规则的流程

1. 照常用 `iptables` 命令增删改规则。
2. 确认无误后重新保存：

   ```bash
   sudo iptables-save | sudo tee /etc/sysconfig/iptables
   ```

3. （可选）立刻重载验证：

   ```bash
   sudo systemctl restart iptables-restore.service
   ```

## 补充：Tailscale ACL 负责“哪个 Tailscale 设备可以访问”

上面的 iptables 规则解决的是：
- **从哪些“网络接口/来源”可以访问 SSH 端口**（只允许 tailscale0）。

如果 tailnet 里还有其他机器，你不想让它们都能 SSH 这台 VPS，可以在 tailscale.com 的 ACL 中进一步限制：

1. 在 VPS 上确认 Tailscale IP（例如 `100.x.y.z`）。
2. 在 Tailscale 管理后台（https://login.tailscale.com）里，在 Access controls 中添加类似规则：

   ```json
   {
     "acls": [
       {
         "action": "accept",
         "src": [
           "user:you@example.com"
         ],
         "dst": [
           "100.x.y.z:2222"
         ]
       }
     ]
   }
   ```

这样就实现了双重安全：
- VPS 本地 iptables：**只允许来自 Tailscale 接口的 SSH**，公网完全屏蔽。
- Tailscale ACL：在 Tailscale 内部再做“账号 / 设备白名单”。
