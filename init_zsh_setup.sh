#!/bin/bash

# ==============================================================================
# init_zsh_setup.sh (同时兼容 Debian / Ubuntu)
# 自动化配置 zsh、时区、Docker、BBR 及 zsz 管理菜单
# ==============================================================================

gl_hui='\033[37m'
gl_hong='\033[31m'
gl_lv='\033[32m'
gl_huang='\033[33m'
gl_lan='\033[34m'
gl_bai='\033[0m'
gl_zi='\033[35m'
gl_kjlan='\033[96m'

# 1. 要求在 root 权限下进行
if [ "$EUID" -ne 0 ]; then
  echo -e "${gl_huang}请使用 root 权限运行此脚本 (例如使用: sudo ./init_zsh_setup.sh)${gl_bai}"
  exit 1
fi

# 切换到 root 根目录
cd /root || { echo -e "${gl_hong}无法切换到 /root 目录${gl_bai}"; exit 1; }

# 获取脚本自身绝对路径，用于后续 zsz 菜单调用和更新
SCRIPT_SELF_PATH=$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")

ensure_netfilter_persistent() {
  if command -v netfilter-persistent >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v apt >/dev/null 2>&1; then
    echo -e "${gl_huang}未找到 apt，跳过 netfilter-persistent 安装。${gl_bai}"
    return 1
  fi

  echo -e "${gl_kjlan}正在安装 netfilter-persistent...${gl_bai}"
  if command -v debconf-set-selections >/dev/null 2>&1; then
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
  fi
  DEBIAN_FRONTEND=noninteractive apt install -y netfilter-persistent iptables-persistent
}

clear_firewall_rules() {
  echo -e "${gl_kjlan}================ 正在关闭并清除防火墙规则 ================${gl_bai}"
  ensure_netfilter_persistent
  systemctl stop firewalld.service >/dev/null 2>&1
  systemctl disable firewalld.service >/dev/null 2>&1
  setenforce 0 >/dev/null 2>&1          # 关闭SELinux
  ufw disable >/dev/null 2>&1           # 关闭Ubuntu的ufw防火墙
  iptables -P INPUT ACCEPT >/dev/null 2>&1      # 设置默认策略为接受
  iptables -P FORWARD ACCEPT >/dev/null 2>&1
  iptables -P OUTPUT ACCEPT >/dev/null 2>&1
  iptables -t mangle -F >/dev/null 2>&1         # 清除所有规则
  iptables -t mangle -X >/dev/null 2>&1
  iptables -t nat -F >/dev/null 2>&1
  iptables -t nat -X >/dev/null 2>&1
  iptables -F >/dev/null 2>&1
  iptables -X >/dev/null 2>&1
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1     # 保存iptables规则
  fi
  echo -e "${gl_lv}防火墙关闭与 iptables 规则清理完成。${gl_bai}"
}

# ================= 设置时区为上海 =================
echo -e "${gl_kjlan}================ 正在设置系统时区为上海 ================${gl_bai}"
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo "Asia/Shanghai" > /etc/timezone
if command -v timedatectl >/dev/null 2>&1; then
  timedatectl set-timezone Asia/Shanghai
fi
echo -e "${gl_lv}当前系统时间: $(date)${gl_bai}"

# ================= 设置 Hostname =================
echo -ne "${gl_huang}请输入您想设置的主机名 (Hostname) [直接回车默认为: master]: ${gl_bai}"
read -r user_hostname
user_hostname=${user_hostname:-master}
hostnamectl set-hostname "$user_hostname"

# ================= 开启 root 密码登录 =================
if [ -f /etc/os-release ]; then
  . /etc/os-release
  if [ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ]; then
    echo -e "${gl_kjlan}================ 正在配置 Root 密码与 SSH 登录 ================${gl_bai}"
    echo -ne "${gl_huang}请输入新的 root 密码 [直接回车默认为: zszxc123@]: ${gl_bai}"
    read -r user_root_pwd
    user_root_pwd=${user_root_pwd:-zszxc123@}
    echo "root:$user_root_pwd" | chpasswd
    
    if [ -f /etc/ssh/sshd_config ]; then
      sed -i 's/^[[:space:]]*#\?[[:space:]]*PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
      sed -i 's/^[[:space:]]*#\?[[:space:]]*PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
    fi
    rm -rf /etc/ssh/sshd_config.d/* /etc/ssh/ssh_config.d/*
    systemctl restart sshd || systemctl restart ssh
  fi
fi

# 阻止交互式对话框
export DEBIAN_FRONTEND=noninteractive

# 2.1 更新系统
echo -e "${gl_kjlan}================ 2.1 更新系统 ================${gl_bai}"
apt -y update

# ================= 关闭并清除防火墙 =================
clear_firewall_rules

# 2.2 安装依赖
echo -e "${gl_kjlan}================ 2.2 安装基础依赖 ================${gl_bai}"
apt install -y zsh git wget curl

# 2.3 安装 oh-my-zsh
echo -e "${gl_kjlan}================ 2.3 安装 oh-my-zsh ================${gl_bai}"
if [ ! -d "/root/.oh-my-zsh" ]; then
  env RUNZSH=no CHSH=no sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi
zsh_path=$(command -v zsh)
if [ -n "$zsh_path" ]; then
  chsh -s "$zsh_path"
fi

# 2.4 更改配置
echo -e "${gl_kjlan}更换 ZSH 主题为 pygmalion...${gl_bai}"
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="pygmalion"/' /root/.zshrc

# 安装 zoxide & fzf
apt -y install zoxide || curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
if [ ! -d "$HOME/.fzf" ]; then
  git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
  ~/.fzf/install --all --no-bash --no-fish --key-bindings --completion --update-rc
fi

# 插件配置
ZSH_CUSTOM=${ZSH_CUSTOM:-/root/.oh-my-zsh/custom}
[ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ] && git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions
[ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ] && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting

if grep -q '^plugins=(' /root/.zshrc; then
  sed -i 's/^plugins=(.*)/plugins=(git extract zsh-autosuggestions zsh-syntax-highlighting)/' /root/.zshrc
else
  echo 'plugins=(git extract zsh-autosuggestions zsh-syntax-highlighting)' >> /root/.zshrc
fi

# 写入自定义 Alias
if ! grep -q "zoxide init" /root/.zshrc; then
cat << 'EOF' >> /root/.zshrc
alias vzsh="vim ~/.zshrc"
alias szsh="source ~/.zshrc"
alias czsh="cat ~/.zshrc"
alias cls="clear"
alias his="history"
export PATH="$HOME/.local/bin:$HOME/.fzf/bin:$PATH"
eval "$(zoxide init zsh)"
EOF
fi

# ================================================================
# 安装 zsz 快捷菜单
# ================================================================
cat > /usr/local/bin/zsz <<'EOF'
#!/bin/bash
# 菜单脚本
SCRIPT_URL="https://raw.githubusercontent.com/Nodewebzsz/Rule/refs/heads/main/init_zsh_setup.sh"
INIT_SCRIPT_PATH="__INIT_SCRIPT_PATH__"

gl_hui='\033[37m'
gl_hong='\033[31m'
gl_lv='\033[32m'
gl_huang='\033[33m'
gl_lan='\033[34m'
gl_bai='\033[0m'
gl_zi='\033[35m'
gl_kjlan='\033[96m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${gl_huang}请使用 root 权限运行 zsz${gl_bai}"
  exit 1
fi

# --- 内部功能函数 ---
update_self() {
    echo -e "${gl_kjlan}正在从远程获取最新版本...${gl_bai}"
    tmp_file=$(mktemp)
    tmp_menu=$(mktemp)
    if curl -fsSL \
        -H "Cache-Control: no-cache" \
        -H "Pragma: no-cache" \
        "${SCRIPT_URL}?t=$(date +%s)" -o "$tmp_file"; then
        if grep -q "#!/bin/bash" "$tmp_file"; then
            remote_menu_tip=$(grep -m1 'action_message="默认出口网卡查询完成' "$tmp_file" 2>/dev/null | sed 's/^[[:space:]]*//')
            if [ -n "$remote_menu_tip" ]; then
                echo -e "${gl_huang}远程脚本菜单文案: ${remote_menu_tip}${gl_bai}"
            fi
            mv "$tmp_file" "$INIT_SCRIPT_PATH"
            chmod +x "$INIT_SCRIPT_PATH"
            echo -e "${gl_lv}脚本更新成功！正在重新安装菜单以应用更改...${gl_bai}"
            if awk 'found && $0 == "EOF" { exit } found { print } index($0, "cat > /usr/local/bin/zsz <<") == 1 { found=1 }' "$INIT_SCRIPT_PATH" > "$tmp_menu" && [ -s "$tmp_menu" ]; then
                escaped_path=$(printf '%s\n' "$INIT_SCRIPT_PATH" | sed 's/[\/&]/\\&/g')
                sed -i "s|__INIT_SCRIPT_PATH__|${escaped_path}|g" "$tmp_menu"
                chmod +x "$tmp_menu"
                mv "$tmp_menu" /usr/local/bin/zsz
                echo -e "${gl_lv}菜单更新完成，正在载入新版菜单...${gl_bai}"
                exec /usr/local/bin/zsz
            fi
            rm -f "$tmp_menu"
            echo -e "${gl_hong}菜单重装失败，请手动执行: bash $INIT_SCRIPT_PATH${gl_bai}"
            return 1
        fi
    fi
    echo -e "${gl_hong}更新失败，请检查网络。${gl_bai}"
    rm -f "$tmp_file" "$tmp_menu"
    return 1
}

install_add_docker() {
    if command -v docker >/dev/null 2>&1; then
        if docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1; then
            echo -e "${gl_lv}Docker 与 Docker Compose 已安装，跳过重复安装流程。${gl_bai}"
            docker --version 2>/dev/null
            docker compose version 2>/dev/null || docker-compose --version 2>/dev/null
            return 0
        fi
        echo -e "${gl_huang}检测到 Docker 已安装，但 Docker Compose 不完整，继续安装/修复 Compose。${gl_bai}"
    fi
    echo -e "${gl_kjlan}正在安装 Docker 环境...${gl_bai}"
    bash <(curl -sSL https://linuxmirrors.cn/docker.sh) --install-latest true --ignore-backup-tips
}

ensure_netfilter_persistent() {
    if command -v netfilter-persistent >/dev/null 2>&1; then
        return 0
    fi

    if ! command -v apt >/dev/null 2>&1; then
        echo -e "${gl_huang}未找到 apt，跳过 netfilter-persistent 安装。${gl_bai}"
        return 1
    fi

    echo -e "${gl_kjlan}正在安装 netfilter-persistent...${gl_bai}"
    if command -v debconf-set-selections >/dev/null 2>&1; then
        echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
        echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    fi
    DEBIAN_FRONTEND=noninteractive apt install -y netfilter-persistent iptables-persistent
}

setup_xboard_forward() {
    if iptables -t nat -C PREROUTING -p udp --dport 50000:65535 -j DNAT --to-destination :8899 >/dev/null 2>&1; then
        echo -e "${gl_lv}xboard 端口转发规则已存在，跳过重复设置。${gl_bai}"
        return 0
    fi

    echo -e "${gl_kjlan}设置端口转发...${gl_bai}"
    ensure_netfilter_persistent
    iptables -t nat -A PREROUTING -p udp --dport 50000:65535 -j DNAT --to-destination :8899
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save
    fi
    echo -e "${gl_lv}xboard 端口转发设置完成。${gl_bai}"
}

firewall_rules_already_clear() {
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet firewalld.service; then
        return 1
    fi

    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qw active; then
        return 1
    fi

    if ! command -v iptables >/dev/null 2>&1; then
        return 0
    fi

    iptables -S 2>/dev/null | grep -Ev '^-(P INPUT ACCEPT|P FORWARD ACCEPT|P OUTPUT ACCEPT)$' | grep -q . && return 1
    iptables -t nat -S 2>/dev/null | grep -Ev '^-(P PREROUTING ACCEPT|P INPUT ACCEPT|P OUTPUT ACCEPT|P POSTROUTING ACCEPT)$' | grep -q . && return 1
    iptables -t mangle -S 2>/dev/null | grep -Ev '^-(P PREROUTING ACCEPT|P INPUT ACCEPT|P FORWARD ACCEPT|P OUTPUT ACCEPT|P POSTROUTING ACCEPT)$' | grep -q . && return 1

    return 0
}

clear_firewall_rules() {
    if firewall_rules_already_clear; then
        echo -e "${gl_lv}防火墙已关闭，iptables 规则已清空，跳过重复清理。${gl_bai}"
        return 0
    fi

    echo -e "${gl_kjlan}正在关闭并清除防火墙规则...${gl_bai}"
    ensure_netfilter_persistent
    systemctl stop firewalld.service >/dev/null 2>&1
    systemctl disable firewalld.service >/dev/null 2>&1
    setenforce 0 >/dev/null 2>&1
    ufw disable >/dev/null 2>&1
    iptables -P INPUT ACCEPT >/dev/null 2>&1
    iptables -P FORWARD ACCEPT >/dev/null 2>&1
    iptables -P OUTPUT ACCEPT >/dev/null 2>&1
    iptables -t mangle -F >/dev/null 2>&1
    iptables -t mangle -X >/dev/null 2>&1
    iptables -t nat -F >/dev/null 2>&1
    iptables -t nat -X >/dev/null 2>&1
    iptables -F >/dev/null 2>&1
    iptables -X >/dev/null 2>&1
    if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save >/dev/null 2>&1
    fi
    echo -e "${gl_lv}防火墙关闭与 iptables 规则清理完成。${gl_bai}"
}

bbr_on() {
    current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [ "$current_qdisc" = "fq" ] && [ "$current_cc" = "bbr" ]; then
        echo -e "${gl_lv}BBR 已开启，跳过重复设置。${gl_bai}"
        return 0
    fi

    kernel_major=$(uname -r | cut -d. -f1)
    kernel_minor=$(uname -r | cut -d. -f2 | sed 's/[^0-9].*//')
    kernel_major=${kernel_major:-0}
    kernel_minor=${kernel_minor:-0}
    if [ "$kernel_major" -lt 4 ] || { [ "$kernel_major" -eq 4 ] && [ "$kernel_minor" -lt 9 ]; }; then
        echo -e "${gl_huang}当前内核版本 $(uname -r) 低于 4.9，不支持原生 BBR，已跳过。${gl_bai}"
        return 1
    fi

    if ! sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
        modprobe tcp_bbr 2>/dev/null
    fi

    if ! sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
        echo -e "${gl_huang}当前内核未提供 bbr 拥塞控制算法，已跳过。${gl_bai}"
        return 1
    fi

    echo -e "${gl_kjlan}开启 BBR...${gl_bai}"
    local_conf="/etc/sysctl.d/99-zsz-bbr.conf"
    mkdir -p /etc/sysctl.d
    echo "net.core.default_qdisc=fq" > "$local_conf"
    echo "net.ipv4.tcp_congestion_control=bbr" >> "$local_conf"

    # 清理旧位置里的同名配置，避免 sysctl --system 时被后续文件覆盖。
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf 2>/dev/null

    mkdir -p /etc/modules-load.d
    echo "tcp_bbr" > /etc/modules-load.d/bbr.conf 2>/dev/null

    if sysctl -p "$local_conf" >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1; then
        current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
        current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
        echo -e "${gl_lv}BBR 设置完成，当前状态: ${gl_huang}$current_cc $current_qdisc${gl_bai}"
        return 0
    fi

    echo -e "${gl_hong}BBR 设置失败，请检查 sysctl 是否支持相关参数。${gl_bai}"
    return 1
}

pause_or_exit() {
    action_status=${1:-0}
    action_message=${2:-"菜单功能执行完成。"}
    echo
    if [ "$action_status" -eq 0 ]; then
        echo -e "${gl_lv}${action_message}${gl_bai}"
    else
        echo -e "${gl_hong}${action_message}${gl_bai}"
        echo -e "${gl_huang}请查看上方输出，确认失败原因后再重试。${gl_bai}"
    fi
    echo -ne "${gl_huang}按任意键返回菜单，按 ESC 退出...${gl_bai}"
    IFS= read -rsn1 key
    echo
    if [ "$key" = $'\e' ]; then
        exit 0
    fi
    clear
}

show_zsz_menu() {
  while true; do
    clear
    echo -e "${gl_kjlan}================ zsz 工具菜单 ================${gl_bai}"
    echo -e "${gl_huang}1.${gl_bai} 执行 init_zsh_setup 主流程 (重置/修复配置)"
    echo -e "${gl_huang}2.${gl_bai} 安装/更新 Docker 与 Docker Compose"
    echo -e "${gl_huang}3.${gl_bai} 输出默认出口网卡"
    echo -e "${gl_huang}4.${gl_bai} xboard 端口转发设置"
    echo -e "${gl_huang}5.${gl_bai} 开启 BBR"
    echo -e "${gl_huang}6.${gl_bai} 关闭并清除防火墙规则"
    echo -e "${gl_huang}7.${gl_bai} 🔄 更新此脚本 (Update Script)"
    echo -e "${gl_huang}0.${gl_bai} 退出"
    echo -e "${gl_kjlan}===============================================${gl_bai}"
    echo -ne "${gl_huang}请输入选择，或按 ESC 退出: ${gl_bai}"
    IFS= read -rsn1 sub_choice
    echo
    if [ "$sub_choice" = $'\e' ]; then
      exit 0
    fi
    action_status=0
    action_message="菜单功能执行完成。"
    case "$sub_choice" in
      1)
        bash "$INIT_SCRIPT_PATH"
        action_status=$?
        action_message="init_zsh_setup 主流程执行完成。"
        ;;
      2)
        install_add_docker
        action_status=$?
        action_message="Docker 与 Docker Compose 安装/检查流程完成。"
        ;;
      3)
        ip route get 1.1.1.1
        action_status=$?
        action_message="默认出口网卡查询完成"
        ;;
      4)
        setup_xboard_forward
        action_status=$?
        action_message="xboard 端口转发设置/检查流程完成。"
        ;;
      5)
        bbr_on
        action_status=$?
        action_message="BBR 开启/检查流程完成。"
        ;;
      6)
        clear_firewall_rules
        action_status=$?
        action_message="防火墙关闭与 iptables 清理流程完成。"
        ;;
      7)
        update_self
        action_status=$?
        action_message="脚本更新流程完成；重新打开 zsz 可加载最新菜单脚本。"
        ;;
      0) exit 0 ;;
      *)
        action_status=1
        action_message="无效选择，请输入菜单中的编号。"
        ;;
    esac
    pause_or_exit "$action_status" "$action_message"
  done
}
show_zsz_menu
EOF

# 替换路径变量并赋权
escaped_path=$(printf '%s\n' "$SCRIPT_SELF_PATH" | sed 's/[\/&]/\\&/g')
sed -i "s|__INIT_SCRIPT_PATH__|${escaped_path}|g" /usr/local/bin/zsz
chmod +x /usr/local/bin/zsz

echo -e "\033[1;32m🎉 配置完成！时区已设为上海，输入 'zsz' 即可调出菜单。\033[0m"
echo -e "\033[1;35m执行 'exec zsh' 立即进入新环境。\033[0m"
