#!/usr/bin/env bash
# Ultra full AlmaLinux VPS bootstrap script for RackNerd-style small VPS
# Run as root: bash init_alma_ultra_full.sh

set -euo pipefail

# 日志记录
LOG_FILE="/var/log/vps_init_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE")
exec 2>&1
echo "[*] 日志将保存到: $LOG_FILE"

### ===== 0. 基本检查 =====
if [[ $EUID -ne 0 ]]; then
  echo "请用 root 运行此脚本（sudo -i 然后再执行）。"
  exit 1
fi

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  if [[ "${ID:-}" != "almalinux" ]]; then
    echo "警告：当前系统不是 AlmaLinux (ID=${ID:-unknown})，脚本可能不完全适用。"
    read -rp "仍然继续? [y/N]: " CONT
    [[ "${CONT,,}" == "y" ]] || exit 1
  fi
fi

DNF_CMD=$(command -v dnf || command -v yum)

if [[ -z "${DNF_CMD}" ]]; then
  echo "未找到 dnf 或 yum，本脚本仅适用于 AlmaLinux / RHEL 系列。"
  exit 1
fi

# 网络连接检查
echo "[*] 检查网络连接..."
if ! curl -s --connect-timeout 5 https://www.google.com > /dev/null 2>&1; then
  echo "[!] 警告：网络连接可能存在问题，某些安装步骤可能会失败。"
  read -rp "是否继续? [y/N]: " CONT
  [[ "${CONT,,}" == "y" ]] || exit 1
else
  echo "[*] 网络连接正常。"
fi

CONFIG_FILE="/root/.alma_vps_init.conf"
USE_PREV_CONFIG="n"
SSHD_READY=0

if [[ -f "${CONFIG_FILE}" ]]; then
  echo "[*] 检测到上一次运行保存的配置：${CONFIG_FILE}"
  # shellcheck disable=SC1090
  . "${CONFIG_FILE}"
  echo "  上次使用的主机名:      ${NEW_HOSTNAME:-alma-vps}"
  echo "  上次使用的用户名:      ${NEW_USER:-noah}"
  echo "  上次使用的 SSH 端口:   ${SSH_PORT:-2222}"
  echo "  上次关闭 22 端口:      ${CLOSE_SSH_22:-n}"
  echo "  上次关闭 ping:         ${DISABLE_PING:-n}"
  echo "  上次启用 BBR:          ${ENABLE_BBR:-n}"
  echo "  上次禁用 SELinux:      ${DISABLE_SELINUX:-n}"
  echo "  上次安装 Tailscale:    ${INSTALL_TAILSCALE:-y}"
  echo "  上次安装 Docker:       ${INSTALL_DOCKER:-y}"
  echo "  上次准备 Doom Emacs:   ${PREPARE_DOOM:-y}"
  echo "  上次安装监控栈:        ${INSTALL_MON:-y}"
  echo "  上次安装 Caddy:        ${INSTALL_CADDY:-y}"
  echo "  上次开放 Netdata 19999: ${OPEN_NETDATA_PORT:-n}"
  read -rp "是否直接使用上述配置并跳过参数输入？[Y/n]: " USE_PREV_CONFIG
  USE_PREV_CONFIG=${USE_PREV_CONFIG:-y}
fi

### ===== 1. 交互式参数确认 =====
if [[ "${USE_PREV_CONFIG,,}" != "y" ]]; then
  read -rp "设置主机名（默认：${NEW_HOSTNAME:-alma-vps}）: " TMP
  NEW_HOSTNAME=${TMP:-${NEW_HOSTNAME:-alma-vps}}

  read -rp "创建的普通用户名（默认：${NEW_USER:-noah}）: " TMP
  NEW_USER=${TMP:-${NEW_USER:-noah}}

  read -rp "SSH 端口（默认：${SSH_PORT:-2222}）: " TMP
  SSH_PORT=${TMP:-${SSH_PORT:-2222}}

  read -rp "是否在防火墙中关闭默认 SSH 端口 22？[y/N]: " TMP
  CLOSE_SSH_22=${TMP:-${CLOSE_SSH_22:-n}}

  echo
  read -rp "是否关闭 ping (ICMP echo)？[y/N]: " TMP
  DISABLE_PING=${TMP:-${DISABLE_PING:-n}}

  read -rp "是否启用 TCP BBR 拥塞控制？[y/N]: " TMP
  ENABLE_BBR=${TMP:-${ENABLE_BBR:-n}}

  read -rp "是否禁用 SELinux？[y/N] (需要重启后生效): " TMP
  DISABLE_SELINUX=${TMP:-${DISABLE_SELINUX:-n}}

  echo
  read -rp "是否安装 Tailscale？[Y/n]: " TMP
  INSTALL_TAILSCALE=${TMP:-${INSTALL_TAILSCALE:-y}}

  read -rp "是否安装 Docker (docker-ce + compose 插件)？[Y/n]: " TMP
  INSTALL_DOCKER=${TMP:-${INSTALL_DOCKER:-y}}

  read -rp "是否准备 Doom Emacs 环境（clone 仓库 + 生成安装脚本）？[Y/n]: " TMP
  PREPARE_DOOM=${TMP:-${PREPARE_DOOM:-y}}

  read -rp "是否安装监控栈：Netdata + vnstat + btop + glances + ncdu + fail2ban？[Y/n]: " TMP
  INSTALL_MON=${TMP:-${INSTALL_MON:-y}}

  read -rp "是否安装 Caddy 作为通用 Web 服务器 / 反向代理？[Y/n]: " TMP
  INSTALL_CADDY=${TMP:-${INSTALL_CADDY:-y}}

  read -rp "是否将 Netdata Web 端口 19999 对公网开放？[y/N]: " TMP
  OPEN_NETDATA_PORT=${TMP:-${OPEN_NETDATA_PORT:-n}}
fi

# 基础参数合法性校验
if ! [[ "${NEW_HOSTNAME}" =~ ^[a-zA-Z0-9.-]+$ ]]; then
  echo "主机名不合法，仅允许字母、数字、点和连字符：${NEW_HOSTNAME}"
  exit 1
fi

if ! [[ "${NEW_USER}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
  echo "用户名不合法，应以字母或下划线开头，仅包含小写字母、数字、下划线和连字符：${NEW_USER}"
  exit 1
fi

if ! [[ "${SSH_PORT}" =~ ^[0-9]+$ ]]; then
  echo "SSH 端口必须是数字：${SSH_PORT}"
  exit 1
fi

if (( SSH_PORT < 1 || SSH_PORT > 65535 )); then
  echo "SSH 端口必须是 1–65535 之间的整数：${SSH_PORT}"
  exit 1
fi

echo
echo "=== 将使用以下设置 ==="
echo "  主机名:          ${NEW_HOSTNAME}"
echo "  用户名:          ${NEW_USER}"
echo "  SSH 端口:        ${SSH_PORT}"
echo "  关闭 22 端口:    ${CLOSE_SSH_22}"
echo "  关闭 ping:       ${DISABLE_PING}"
echo "  启用 BBR:        ${ENABLE_BBR}"
echo "  禁用 SELinux:    ${DISABLE_SELINUX}"
echo "  安装 Tailscale:  ${INSTALL_TAILSCALE}"
echo "  安装 Docker:     ${INSTALL_DOCKER}"
echo "  准备 Doom Emacs: ${PREPARE_DOOM}"
echo "  安装监控栈:      ${INSTALL_MON}"
echo "  安装 Caddy:      ${INSTALL_CADDY}"
echo "  Netdata 开放公网: ${OPEN_NETDATA_PORT}"
echo

echo "[*] 将当前参数保存到 ${CONFIG_FILE}，以便下次运行快速复用..."
cat > "${CONFIG_FILE}" <<EOF
NEW_HOSTNAME=${NEW_HOSTNAME}
NEW_USER=${NEW_USER}
SSH_PORT=${SSH_PORT}
CLOSE_SSH_22=${CLOSE_SSH_22}
DISABLE_PING=${DISABLE_PING}
ENABLE_BBR=${ENABLE_BBR}
DISABLE_SELINUX=${DISABLE_SELINUX}
INSTALL_TAILSCALE=${INSTALL_TAILSCALE}
INSTALL_DOCKER=${INSTALL_DOCKER}
PREPARE_DOOM=${PREPARE_DOOM}
INSTALL_MON=${INSTALL_MON}
INSTALL_CADDY=${INSTALL_CADDY}
OPEN_NETDATA_PORT=${OPEN_NETDATA_PORT}
EOF

read -rp "确认无误后继续? [y/N]: " OK
[[ "${OK,,}" == "y" ]] || { echo "已取消。"; exit 1; }

echo
echo "=== 开始初始化 AlmaLinux VPS ==="
sleep 1

### ===== 2. 设置主机名 =====
echo "[*] 设置主机名为 ${NEW_HOSTNAME}"
hostnamectl set-hostname "${NEW_HOSTNAME}"

### ===== 3. 更新系统 & 基础软件 =====
echo "[*] 更新软件源与系统..."
$DNF_CMD -y clean all
$DNF_CMD -y makecache
if ! $DNF_CMD -y update; then
  echo "[!] 系统更新时遇到依赖/冲突问题，尝试使用 --skip-broken 继续更新其余软件包..."
  if ! $DNF_CMD -y update --skip-broken; then
    echo "[!] 使用 --skip-broken 更新仍然失败，请稍后手动检查 dnf 输出（例如尝试：dnf -y update --allowerasing），脚本将继续执行后续步骤。"
  fi
fi

echo "[*] 安装 EPEL 与开发工具..."
$DNF_CMD -y install epel-release
$DNF_CMD -y groupinstall "Development Tools"

echo "[*] 安装常用工具..."
$DNF_CMD -y install \
  sudo vim neovim \
  lsof firewalld \
  git wget curl \
  zsh lua tar \
  fzf which unzip tmux \
  emacs ripgrep \
  htop btop

### ===== 4. SELinux 设置 =====
if [[ "${DISABLE_SELINUX,,}" == "y" ]]; then
  echo "[*] 禁用 SELinux..."
  if command -v setenforce &>/dev/null; then
    setenforce 0 || true
  fi
  if [[ -f /etc/selinux/config ]]; then
    sed -ri 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
    sed -ri 's/^SELINUX=permissive/SELINUX=disabled/' /etc/selinux/config
  fi
else
  echo "[i] 保持 SELinux 当前状态（未强制禁用）。"
fi

### ===== 5. sysctl 调优：ICMP / BBR =====
SYSCTL_FILE="/etc/sysctl.d/99-custom-tuning.conf"
echo "[*] 写入内核参数到 ${SYSCTL_FILE}"
{
  echo "# Custom networking tunings"
  if [[ "${DISABLE_PING,,}" == "y" ]]; then
    echo "net.ipv4.icmp_echo_ignore_all = 1"
  fi
  if [[ "${ENABLE_BBR,,}" == "y" ]]; then
    echo "net.core.default_qdisc = fq"
    echo "net.ipv4.tcp_congestion_control = bbr"
  fi
} > "${SYSCTL_FILE}"

if [[ "${ENABLE_BBR,,}" == "y" ]]; then
  if [[ -r /proc/sys/net/ipv4/tcp_available_congestion_control ]]; then
    if ! grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control; then
      echo "[!] 检测到当前内核 tcp_available_congestion_control 中未包含 bbr，BBR 可能无法成功启用。"
    fi
  else
    echo "[i] 无法检测内核是否支持 BBR（缺少 /proc/sys/net/ipv4/tcp_available_congestion_control），请手动确认内核版本。"
  fi
fi

echo "[*] 应用 sysctl 设置..."
sysctl --system || sysctl -p || true

### ===== 6. Firewalld 配置 =====
echo "[*] 启用 firewalld 并设置开机自启..."
systemctl enable --now firewalld || true

echo "[*] 在 firewall 中开放 SSH 端口 ${SSH_PORT}/tcp..."
firewall-cmd --permanent --add-port="${SSH_PORT}"/tcp || true
firewall-cmd --reload || true

### ===== 7. 创建普通用户并加入 wheel 组 =====
if id "${NEW_USER}" &>/dev/null; then
  echo "[i] 用户 ${NEW_USER} 已存在，跳过创建和密码设置。"
else
  echo "[*] 创建新用户 ${NEW_USER} ..."
  adduser "${NEW_USER}"
  echo "[*] 为 ${NEW_USER} 设置密码（请在提示时输入两遍）："
  passwd "${NEW_USER}"
fi

echo "[*] 将 ${NEW_USER} 加入 wheel 组（sudo 权限）..."
usermod -aG wheel "${NEW_USER}"

echo "[*] 如 root 已配置 SSH 公钥，则为 ${NEW_USER} 同步相同的 authorized_keys..."
if [[ -f /root/.ssh/authorized_keys ]]; then
  install -d -m 700 "/home/${NEW_USER}/.ssh"
  # 如新用户已有 authorized_keys，则只添加不存在的公钥；否则创建
  if [[ -f "/home/${NEW_USER}/.ssh/authorized_keys" ]]; then
    # 使用 grep 过滤已存在的公钥，避免重复
    grep -Fxvf "/home/${NEW_USER}/.ssh/authorized_keys" /root/.ssh/authorized_keys >> "/home/${NEW_USER}/.ssh/authorized_keys" 2>/dev/null || true
  else
    install -m 600 /root/.ssh/authorized_keys "/home/${NEW_USER}/.ssh/authorized_keys"
  fi
  chown -R "${NEW_USER}:${NEW_USER}" "/home/${NEW_USER}/.ssh"
fi

echo "[*] 确保 wheel 组有 sudo 权限..."
if ! grep -Eq '^[^#]*%wheel\s+ALL=\(ALL\)\s+ALL' /etc/sudoers; then
  sed -ri 's/^#\s*(%wheel\s+ALL=\(ALL\)\s+ALL)/\1/' /etc/sudoers || true
fi

### ===== 8. SSH 配置：端口 + 禁 root 登录 + 暂保留密码登录 =====
SSHD_CONFIG="/etc/ssh/sshd_config"

echo "[*] 调整 SSH 配置 (${SSHD_CONFIG})..."

# 备份一份原始 sshd 配置，便于出错时手动恢复
if [[ -f "${SSHD_CONFIG}" && ! -f "${SSHD_CONFIG}.vps-init.bak" ]]; then
  cp "${SSHD_CONFIG}" "${SSHD_CONFIG}.vps-init.bak"
  echo "[*] 已备份原始 SSH 配置到 ${SSHD_CONFIG}.vps-init.bak"
fi

# 端口
if grep -Eq '^[#\s]*Port\s' "${SSHD_CONFIG}"; then
  sed -ri "s/^[#\s]*Port\s+.*/Port ${SSH_PORT}/" "${SSHD_CONFIG}"
else
  echo "Port ${SSH_PORT}" >> "${SSHD_CONFIG}"
fi

# 禁止 root 登录
if grep -Eq '^[#\s]*PermitRootLogin\s' "${SSHD_CONFIG}"; then
  sed -ri "s/^[#\s]*PermitRootLogin\s+.*/PermitRootLogin no/" "${SSHD_CONFIG}"
else
  echo "PermitRootLogin no" >> "${SSHD_CONFIG}"
fi

# 保留密码登录（你 ssh-copy-id 后再改为 no）
if grep -Eq '^[#\s]*PasswordAuthentication\s' "${SSHD_CONFIG}"; then
  sed -ri "s/^[#\s]*PasswordAuthentication\s+.*/PasswordAuthentication yes/" "${SSHD_CONFIG}"
else
  echo "PasswordAuthentication yes" >> "${SSHD_CONFIG}"
fi

# SELinux 下允许 sshd 使用新端口
SELINUX_STATUS=""
if command -v getenforce &>/dev/null; then
  SELINUX_STATUS=$(getenforce)
fi

if [[ "${SELINUX_STATUS}" == "Enforcing" || "${SELINUX_STATUS}" == "Permissive" ]]; then
  echo "[*] 检测到 SELinux (${SELINUX_STATUS})，尝试为 SSH 新端口 ${SSH_PORT} 配置策略..."
  $DNF_CMD -y install policycoreutils-python-utils &>/dev/null || true
  if command -v semanage &>/dev/null; then
    semanage port -a -t ssh_port_t -p tcp "${SSH_PORT}" 2>/dev/null || \
      semanage port -m -t ssh_port_t -p tcp "${SSH_PORT}" || true
  else
    echo "[!] 未找到 semanage 命令，若 SELinux 为 Enforcing，请手动允许 SSH 新端口："
    echo "    semanage port -a -t ssh_port_t -p tcp ${SSH_PORT}"
  fi
fi

echo "[*] 检测新的 sshd 配置语法..."
if ! sshd -t -q; then
  echo "[!] 新的 /etc/ssh/sshd_config 配置检测失败，已取消自动重启 sshd。"
  echo "    请在当前会话中运行以下命令查看并修复错误："
  echo "      sshd -t"
  echo "      vim ${SSHD_CONFIG}"
  echo "      systemctl restart sshd"
else
  echo "[*] 重启 sshd..."
  if ! systemctl restart sshd; then
    echo "[!] sshd 重启失败，请运行以下命令查看详情："
    echo "    systemctl status sshd.service -l"
    echo "    journalctl -xeu sshd.service"
  else
    SSHD_READY=1
  fi
fi

echo "[*] 当前监听端口："
ss -tlnp | grep sshd || true

if [[ "${CLOSE_SSH_22,,}" == "y" ]]; then
  if [[ "${SSHD_READY}" == "1" ]]; then
    echo "[*] 按选择在 firewalld 中关闭默认 SSH 端口 22..."
    firewall-cmd --permanent --remove-service=ssh &>/dev/null || \
      firewall-cmd --permanent --remove-port=22/tcp &>/dev/null || true
    firewall-cmd --reload || true
  else
    echo "[!] 由于 sshd 未成功通过语法检查或重启，本次不会关闭 firewalld 中的 22 端口，以避免潜在锁死。"
  fi
fi

### ===== 9. 安装 Tailscale（可选） =====
if [[ "${INSTALL_TAILSCALE,,}" == "y" ]]; then
  echo "[*] 安装 Tailscale..."
  if curl -fsSL https://tailscale.com/install.sh | sh; then
    echo "[*] Tailscale 安装成功。登录后可以运行：sudo tailscale up"
  else
    echo "[!] tailscale 安装失败，请稍后手动检查。"
  fi
else
  echo "[i] 跳过安装 Tailscale。"
fi

### ===== 10. 安装 Docker（可选） =====
if [[ "${INSTALL_DOCKER,,}" == "y" ]]; then
  echo "[*] 安装 Docker CE..."
  $DNF_CMD -y install yum-utils

  if ! $DNF_CMD repolist | grep -qi docker-ce; then
    $DNF_CMD config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || true
  fi

  $DNF_CMD -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || {
    echo "[!] Docker 安装失败，请检查仓库配置。"
  }

  echo "[*] 启用并启动 Docker..."
  systemctl enable --now docker || true

  echo "[*] 将 ${NEW_USER} 加入 docker 组..."
  if ! getent group docker >/dev/null 2>&1; then
    groupadd docker || true
  fi
  usermod -aG docker "${NEW_USER}" || true

  echo "[*] Docker 版本："
  docker --version || true
else
  echo "[i] 跳过安装 Docker。"
fi

### ===== 11. 安装监控栈（可选） =====
if [[ "${INSTALL_MON,,}" == "y" ]]; then
  echo "[*] 安装监控相关工具：vnstat / glances / ncdu / fail2ban / netdata ..."

  # 基础监控工具
  $DNF_CMD -y install vnstat glances ncdu fail2ban || true

  # vnstat
  systemctl enable --now vnstat || true

  # fail2ban sshd 基本 jail
  mkdir -p /etc/fail2ban/jail.d
  cat > /etc/fail2ban/jail.d/sshd.conf <<EOF
[sshd]
enabled  = true
port     = ${SSH_PORT}
filter   = sshd
logpath  = /var/log/secure
maxretry = 5
bantime  = 3600
EOF
  systemctl enable --now fail2ban || true

  # Netdata 安装（官方一键）
  echo "[*] 安装 Netdata（可能稍微久一点）..."
  NETDATA_SCRIPT="/tmp/netdata-kickstart.sh"
  if curl -Ss https://get.netdata.cloud/kickstart.sh -o "$NETDATA_SCRIPT"; then
    bash "$NETDATA_SCRIPT" --dont-wait || echo "[!] Netdata 安装失败，请稍后手动检查（参考：https://learn.netdata.cloud/）。"
    rm -f "$NETDATA_SCRIPT"
  else
    echo "[!] Netdata 安装脚本下载失败，跳过安装。"
  fi

  # 默认 Netdata 会监听 19999 端口，可以按需放行或通过 tailscale 访问
  if [[ "${OPEN_NETDATA_PORT,,}" == "y" ]]; then
    echo "[*] 按选择在 firewalld 中开放 Netdata Web 端口 19999/tcp ..."
    firewall-cmd --permanent --add-port=19999/tcp &>/dev/null || true
    firewall-cmd --reload &>/dev/null || true
  else
    echo "[i] Netdata 19999 未对公网开放，推荐通过 Tailscale 或内网访问，或自行配置反向代理。"
  fi
else
  echo "[i] 跳过安装监控栈。"
fi

### ===== 12. 安装 Caddy（可选） =====
if [[ "${INSTALL_CADDY,,}" == "y" ]]; then
  echo "[*] 安装 Caddy..."
  $DNF_CMD -y install caddy || echo "[!] 安装 Caddy 失败，请检查 EPEL 是否可用。"

  systemctl enable --now caddy || true

  echo "[*] 在 firewalld 中开放 HTTP/HTTPS 端口..."
  firewall-cmd --permanent --add-service=http &>/dev/null || true
  firewall-cmd --permanent --add-service=https &>/dev/null || true
  firewall-cmd --reload &>/dev/null || true

  # 给出简单的默认配置示例（不直接覆盖 /etc/caddy/Caddyfile，避免毁掉发行版默认）
  if [[ ! -f /etc/caddy/Caddyfile.example.vps ]]; then
    cat > /etc/caddy/Caddyfile.example.vps <<'EOF'
# 示例：将 your.domain 80/443 反代到本机 8000
your.domain {
    reverse_proxy 127.0.0.1:8000
}
EOF
    echo "[*] 已写入 /etc/caddy/Caddyfile.example.vps 作为参考。"
  fi
else
  echo "[i] 跳过安装 Caddy。"
fi

### ===== 13. 为新用户准备目录结构 =====
echo "[*] 为 ${NEW_USER} 准备常用目录..."
su - "${NEW_USER}" -c 'mkdir -p ~/github ~/apps ~/logs ~/tmp'

### ===== 14. zsh + oh-my-zsh + 插件 + z.lua + powerlevel10k =====
echo "[*] 设置 ${NEW_USER} 默认 shell 为 zsh ..."
ZSH_PATH="$(command -v zsh || true)"
if [[ -n "${ZSH_PATH}" ]]; then
  chsh -s "${ZSH_PATH}" "${NEW_USER}" || echo "[!] chsh 失败，请确认 ${ZSH_PATH} 已在 /etc/shells 中。"
else
  echo "[!] 未找到 zsh 可执行文件，无法为 ${NEW_USER} 设置默认 shell。"
fi

echo "[*] 为 ${NEW_USER} 创建基础 .zshrc（如不存在）..."
su - "${NEW_USER}" -c 'if [[ ! -f ~/.zshrc ]]; then
  cat > ~/.zshrc << "EOF"
export TERM=xterm-256color
export EDITOR=vim

alias ll="ls -alF"
alias la="ls -A"
alias l="ls -CF"
alias quit="exit"
EOF
fi'

echo "[*] 安装 oh-my-zsh..."
su - "${NEW_USER}" -c 'RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"' || \
  echo "[!] oh-my-zsh 安装失败，请稍后在用户下手动执行。"

echo "[*] 安装 zsh 插件：zsh-autosuggestions / zsh-syntax-highlighting ..."
su - "${NEW_USER}" -c '
  ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  mkdir -p "$ZSH_CUSTOM/plugins"
  if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  fi
  if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
  fi
'

echo "[*] 安装 z.lua ..."
su - "${NEW_USER}" -c '
  mkdir -p ~/github
  if [[ ! -d ~/github/z.lua ]]; then
    cd ~/github
    git clone https://github.com/skywind3000/z.lua.git
  fi
'

echo "[*] 安装 powerlevel10k ..."
su - "${NEW_USER}" -c '
  ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  mkdir -p "$ZSH_CUSTOM/themes"
  if [[ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
  fi
'

echo "[*] 更新 ${NEW_USER} 的 .zshrc，启用插件和主题..."
su - "${NEW_USER}" -c '
  ZSHRC="$HOME/.zshrc"

  if ! grep -q "oh-my-zsh.sh" "$ZSHRC"; then
    cat >> "$ZSHRC" << "EOF"

# oh-my-zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)

source "$ZSH/oh-my-zsh.sh"

# z.lua
eval "$(lua $HOME/github/z.lua/z.lua --init zsh)"

# 接受 zsh-autosuggestions 的快捷键
bindkey "," autosuggest-accept
EOF
  else
    sed -ri "s|^ZSH_THEME=.*|ZSH_THEME=\"powerlevel10k/powerlevel10k\"|" "$ZSHRC" || true
    sed -ri "s|^plugins=\(.*\)|plugins=(git zsh-autosuggestions zsh-syntax-highlighting)|" "$ZSHRC" || true
    
    # 分别检查 z.lua 和 bindkey，避免重复
    if ! grep -q "z.lua" "$ZSHRC"; then
      cat >> "$ZSHRC" << "EOF"

# z.lua
eval "$(lua $HOME/github/z.lua/z.lua --init zsh)"
EOF
    fi
    
    if ! grep -q 'bindkey ","' "$ZSHRC"; then
      echo 'bindkey "," autosuggest-accept' >> "$ZSHRC"
    fi
  fi
'

### ===== 15. 准备 Doom Emacs 环境（可选） =====
if [[ "${PREPARE_DOOM,,}" == "y" ]]; then
  echo "[*] 为 ${NEW_USER} 准备 Doom Emacs 环境..."
  su - "${NEW_USER}" -c '
    if [[ ! -d "$HOME/.config/emacs" ]]; then
      mkdir -p "$HOME/.config"
      git clone --depth 1 https://github.com/doomemacs/doomemacs "$HOME/.config/emacs"
    fi

    cat > "$HOME/install_doom.sh" << "EOF"
#!/usr/bin/env bash
set -euo pipefail

if [[ ! -d "$HOME/.config/emacs" ]]; then
  echo "未发现 ~/.config/emacs (doomemacs)，请先确认仓库已克隆。"
  exit 1
fi

if [[ -f "$HOME/.emacs" ]]; then
  echo "检测到 ~/.emacs，将其重命名为 ~/.emacs.pre-doom.bak 以避免与 Doom 冲突。"
  mv "$HOME/.emacs" "$HOME/.emacs.pre-doom.bak"
fi

cd "$HOME/.config/emacs"

yes | ./bin/doom install

echo
echo "Doom Emacs 安装完成。"
echo "如需修改模块，请编辑：~/.config/doom/config.el 及 init.el / packages.el，然后运行："
echo "  ~/.config/emacs/bin/doom sync"
EOF

    chmod +x "$HOME/install_doom.sh"
  '
  echo "[*] Doom Emacs 仓库已准备，${NEW_USER} 登录后执行 ~/install_doom.sh 即可安装。"
else
  echo "[i] 跳过 Doom Emacs 环境准备。"
fi

### ===== 16. 收尾提示 =====
echo
echo "=== 初始化完成 ==="
IP_ADDR=$(hostname -I 2>/dev/null | awk '{print $1}')
echo "服务器 IP(猜测): ${IP_ADDR:-<your-ip>}"
echo
echo "1) 在本地用新端口登录："
echo "   ssh -p ${SSH_PORT} ${NEW_USER}@${IP_ADDR:-<your-ip>}"
echo
echo "2) 部署 SSH 公钥："
echo "   ssh-copy-id -p ${SSH_PORT} ${NEW_USER}@${IP_ADDR:-<your-ip>}"
echo "   确认用密钥可登录后，建议："
echo "     编辑 /etc/ssh/sshd_config: PasswordAuthentication no"
echo "     systemctl restart sshd"
echo
echo "3) Tailscale（如安装）："
echo "   su - ${NEW_USER}"
echo "   sudo tailscale up"
echo
echo "4) Docker（如安装）："
echo "   su - ${NEW_USER}"
echo "   docker run --rm hello-world"
echo
echo "5) Doom Emacs（如准备）："
echo "   su - ${NEW_USER}"
echo "   ./install_doom.sh"
echo
echo "6) Netdata / 监控："
echo "   Netdata Web UI 默认在 19999 端口，可通过 tailscale 访问："
echo "   http://<tailscale-ip>:19999"
echo
echo "最后建议重启一次："
echo "   reboot"
echo "以确保 SELinux / sysctl / BBR 等设置都完全生效。"
