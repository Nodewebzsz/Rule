#!/bin/bash

# ==============================================================================
# init_zsh_setup.sh (同时兼容 Debian / Ubuntu)
# 自动化配置 zsh、时区、Docker、BBR 及 zsz 管理菜单
# ==============================================================================

# 1. 要求在 root 权限下进行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本 (例如使用: sudo ./init_zsh_setup.sh)"
  exit 1
fi

# 切换到 root 根目录
cd /root || { echo "无法切换到 /root 目录"; exit 1; }

# 获取脚本自身绝对路径，用于后续 zsz 菜单调用和更新
SCRIPT_SELF_PATH=$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")

# ================= 设置时区为上海 =================
echo "================ 正在设置系统时区为上海 ================"
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo "Asia/Shanghai" > /etc/timezone
if command -v timedatectl >/dev/null 2>&1; then
  timedatectl set-timezone Asia/Shanghai
fi
echo "当前系统时间: $(date)"

# ================= 设置 Hostname =================
read -r -p "请输入您想设置的主机名 (Hostname) [直接回车默认为: master]: " user_hostname
user_hostname=${user_hostname:-master}
hostnamectl set-hostname "$user_hostname"

# ================= 开启 root 密码登录 =================
if [ -f /etc/os-release ]; then
  . /etc/os-release
  if [ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ]; then
    echo "================ 正在配置 Root 密码与 SSH 登录 ================"
    read -r -p "请输入新的 root 密码 [直接回车默认为: zszxc123@]: " user_root_pwd
    user_root_pwd=${user_root_pwd:-zszxc123@}
    echo "root:$user_root_pwd" | chpasswd
    
    sed -i 's/^[[:space:]]*#\?[[:space:]]*PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
    sed -i 's/^[[:space:]]*#\?[[:space:]]*PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
    rm -rf /etc/ssh/sshd_config.d/* /etc/ssh/ssh_config.d/*
    systemctl restart sshd || systemctl restart ssh
  fi
fi

# 阻止交互式对话框
export DEBIAN_FRONTEND=noninteractive

# 2.1 更新系统
echo "================ 2.1 更新系统 ================"
apt -y update

# 2.2 安装依赖
echo "================ 2.2 安装基础依赖 ================"
apt install -y zsh git wget curl

# 2.3 安装 oh-my-zsh
echo "================ 2.3 安装 oh-my-zsh ================"
if [ ! -d "/root/.oh-my-zsh" ]; then
  env RUNZSH=no CHSH=no sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi
chsh -s $(which zsh)

# 2.4 更改配置
echo "更换 ZSH 主题为 pygmalion..."
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

sed -i 's/^plugins=(git)/plugins=(git extract zsh-autosuggestions zsh-syntax-highlighting)/' /root/.zshrc

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

if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行 zsz"
  exit 1
fi

# --- 内部功能函数 ---
update_self() {
    echo "正在从远程获取最新版本..."
    tmp_file=$(mktemp)
    if curl -sSL "$SCRIPT_URL" -o "$tmp_file"; then
        if grep -q "#!/bin/bash" "$tmp_file"; then
            mv "$tmp_file" "$INIT_SCRIPT_PATH"
            chmod +x "$INIT_SCRIPT_PATH"
            echo "脚本更新成功！正在重新安装菜单以应用更改..."
            bash "$INIT_SCRIPT_PATH"
            exit 0
        fi
    fi
    echo "更新失败，请检查网络。"
}

install_add_docker() {
    echo "正在安装 Docker 环境..."
    bash <(curl -sSL https://linuxmirrors.cn/docker.sh) --install-latest true --ignore-backup-tips
}

setup_xboard_forward() {
    echo "设置端口转发..."
    iptables -t nat -A PREROUTING -p udp --dport 50000:65535 -j DNAT --to-destination :8899
    apt install -y netfilter-persistent iptables-persistent
    netfilter-persistent save
}

bbr_on() {
    echo "开启 BBR..."
    echo "net.core.default_qdisc=fq" > /etc/sysctl.d/99-zsz-bbr.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/99-zsz-bbr.conf
    sysctl --system
}

show_zsz_menu() {
  while true; do
    clear
    echo "================ zsz 工具菜单 ================"
    echo "1. 执行 init_zsh_setup 主流程 (重置/修复配置)"
    echo "2. 安装/更新 Docker 与 Docker Compose"
    echo "3. 输出默认出口网卡"
    echo "4. xboard 端口转发设置"
    echo "5. 开启 BBR"
    echo "6. 🔄 更新此脚本 (Update Script)"
    echo "0. 退出"
    echo "=============================================="
    read -r -p "请输入选择: " sub_choice
    case "$sub_choice" in
      1) bash "$INIT_SCRIPT_PATH" ;;
      2) install_add_docker ;;
      3) ip route get 1.1.1.1 ;;
      4) setup_xboard_forward ;;
      5) bbr_on ;;
      6) update_self ;;
      0) exit 0 ;;
    esac
    read -r -p "按回车键返回..." _
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
