#!/bin/bash

# ==============================================================================
# init_zsh_setup.sh (同时兼容 Debian / Ubuntu)
# 该脚本用于自动化配置 zsh、oh-my-zsh 及相关主题、插件
# 并在 Ubuntu 24.04 及以上版本自动开启 root 密码登录
# 目录跳转工具已由 fasd 升级为现代化的 zoxide，fzf 采用官方 Git 安装避免版本过低
# ==============================================================================

# 1. 要求在 root 权限下进行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本 (例如使用: sudo ./init_zsh_setup.sh，或者直接在 root 账户下执行)"
  exit 1
fi

# 切换到 root 根目录
cd /root || { echo "无法切换到 /root 目录"; exit 1; }
echo "当前目录: $(pwd)"

# ================= 设置 Hostname =================
read -r -p "请输入您想设置的主机名 (Hostname) [直接回车默认为: master]: " user_hostname
user_hostname=${user_hostname:-master}
echo "正在将主机名设置为: $user_hostname ..."
hostnamectl set-hostname "$user_hostname"
# =================================================

# ================= 开启 root 密码登录 =================
if [ -f /etc/os-release ]; then
  . /etc/os-release
  if [ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ]; then
    echo "================ 正在配置 Root 密码与 SSH 登录 ================"
    
    # 1. 修改 root 密码（保留回车使用默认密码的行为）
    if ! id root >/dev/null 2>&1; then
      echo "错误：用户 root 不存在"
      exit 1
    fi
    read -r -p "请输入新的 root 密码 [直接回车默认为: zszxc123@]: " user_root_pwd
    user_root_pwd=${user_root_pwd:-zszxc123@}
    echo "root:$user_root_pwd" | chpasswd
    echo "root 密码已修改成功！"

    # 2. 通用 SSH 配置 (所有版本均执行)
    sed -i 's/^[[:space:]]*#\?[[:space:]]*PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
    sed -i 's/^[[:space:]]*#\?[[:space:]]*PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
    rm -rf /etc/ssh/sshd_config.d/* /etc/ssh/ssh_config.d/*

    # 3. 重启 SSH 服务生效
    systemctl restart sshd || systemctl restart ssh
    echo "SSH 服务已重启！"
    echo "================================================================================"
  fi
fi
# =================================================================================

# 阻止 apt-get/dpkg 安装过程中弹出任何交互式确认对话框（尤其是在 Debian/Ubuntu 的自动安装中）
export DEBIAN_FRONTEND=noninteractive

# 2.1 更新系统
echo "================ 2.1 更新系统 ================"
apt -y update

# 2.2 安装 zsh 和 git 等依赖
echo "================ 2.2 安装 zsh 与 git ================"
apt install -y zsh git wget curl

# 2.3 安装 oh-my-zsh
echo "================ 2.3 安装 oh-my-zsh ================"
# 为了避免 oh-my-zsh 安装后自动进入 zsh 环境导致本脚本执行中断，设置 RUNZSH=no
env RUNZSH=no CHSH=no sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

echo "查看 zsh 安装目录："
which zsh

echo "切换使用的 shell 程序为 zsh："
# 兼容 Debian 和 Ubuntu 的不同路径，使用 $(which zsh) 动态获取路径
chsh -s $(which zsh)

# 2.4 更改 oh-my-zsh 配置
echo "================ 2.4 修改 oh-my-zsh 配置 ================"

# 2.4.1 更换 ZSH 主题
echo "更换 ZSH 主题为 pygmalion..."
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="pygmalion"/' /root/.zshrc

# 2.4.2 安装核心效率工具 (zoxide & fzf)
echo "安装 zoxide 和 fzf (最新源码版)..."

# 1. 安装 zoxide (优先 apt，失败则官方脚本兜底)
apt -y install zoxide || {
  echo "警告: apt 安装 zoxide 失败，正在通过官方脚本下载安装 zoxide..."
  curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
}

# 2. 强制使用官方 Git 脚本安装 fzf (彻底解决 apt 源版本过老导致 zi 报错的问题)
if [ ! -d "$HOME/.fzf" ]; then
  git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
  ~/.fzf/install --all --no-bash --no-fish --key-bindings --completion --update-rc
fi

# 2.4.3 安装并配置 Zsh 插件
echo "克隆 zsh-autosuggestions 和 zsh-syntax-highlighting 插件..."
# 获取 oh-my-zsh 的 custom 目录
ZSH_CUSTOM=${ZSH_CUSTOM:-/root/.oh-my-zsh/custom}
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting

echo "修改 /root/.zshrc 文件中的 plugins 配置..."
# 注意：移除了 fzf 插件，因为官方 install 脚本已完美配置快捷键，保留会报找不到目录的错误
sed -i 's/^plugins=(git)/plugins=(git extract zsh-autosuggestions zsh-syntax-highlighting)/' /root/.zshrc

echo "添加快捷 alias、环境变量和 zoxide 配置..."
cat << 'EOF' >> /root/.zshrc

# 自定义 aliases
alias vzsh="vim ~/.zshrc"
alias szsh="source ~/.zshrc"
alias czsh="cat ~/.zshrc"
alias cls="clear"
alias his="history"
# 将脚本兜底安装的 zoxide 和 git 源码安装的 fzf 可执行文件目录加入 PATH
export PATH="$HOME/.local/bin:$HOME/.fzf/bin:$PATH"

# 初始化并全局注册 zoxide 的智能路径补全
eval "$(zoxide init zsh)"
EOF

# ================================================================
# 终端输出颜色配置
# ================================================================
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
NC='\033[0m' # No Color (恢复默认)

echo -e "\n${GREEN}================================================================${NC}"
echo -e "${GREEN}🎉 配置已全部完成！${NC}\n"

echo -e "${YELLOW}🔥【必备插件指南】🔥${NC}"
echo -e "${CYAN}1. zsh-autosuggestions:${NC} 打字时若出现灰色的历史纪录建议，直接按 ${YELLOW}【向右方向键 →】${NC} 即可补全整行！"
echo -e "${CYAN}2. fzf (必须掌握):${NC} 此乃模糊搜索神器。随时按下 ${YELLOW}【Ctrl + R】${NC}，会弹出一个交互菜单，输入部分命令字母就能极速找到以前敲过的任意长命令，回车即可加载到输入区跳过繁复打字！"
echo -e "${CYAN}3. zoxide (新一代目录跳转神器):${NC} 完全替代 fasd。在终端输入 ${YELLOW}【z 关键字】${NC} 即可根据历史访问习惯瞬间跳到目标目录（例如输入 ${YELLOW}z log${NC}，就能跳到 /var/log）。配合 fzf 还可以输入 ${YELLOW}【zi】${NC} 开启可视化交互跳转！\n"

# 输出默认出口网卡（例如 enp0s6）
default_net_if=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
if [ -n "$default_net_if" ]; then
  echo -e "${CYAN}🌐 当前默认出口网卡: ${YELLOW}${default_net_if}${NC}"
else
  echo -e "${YELLOW}⚠️ 未检测到默认出口网卡，可手动执行: ip route get 1.1.1.1${NC}"
fi

echo -e "${GREEN}💡 为使配置生效，请重新登录 VPS，或者直接在命令行中输入以下命令：${NC}"
echo -e "${MAGENTA}  exec zsh${NC}"
echo -e "\n进去后即可体验全新的极速终端界面！"
echo -e "${GREEN}================================================================${NC}"

# ================================================================
# 安装 zsz 菜单命令（输入 zsz 调出选项，自行选择安装）
# ================================================================
SCRIPT_SELF_PATH=$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")

cat > /usr/local/bin/zsz <<'EOF'
#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行 zsz（例如 sudo zsz）"
  exit 1
fi

INIT_SCRIPT_PATH="__INIT_SCRIPT_PATH__"

service_enable() {
  if command -v apk >/dev/null 2>&1; then
    rc-update add "$1" default >/dev/null 2>&1
  else
    /bin/systemctl enable "$1" >/dev/null 2>&1
  fi
}

service_start() {
  if command -v apk >/dev/null 2>&1; then
    service "$1" start >/dev/null 2>&1
  else
    /bin/systemctl start "$1" >/dev/null 2>&1
  fi
}

service_restart() {
  if command -v apk >/dev/null 2>&1; then
    service "$1" restart >/dev/null 2>&1
  else
    /bin/systemctl restart "$1" >/dev/null 2>&1
  fi
}

install_pkg() {
  if [ $# -eq 0 ]; then
    return 1
  fi

  for package in "$@"; do
    if command -v "$package" >/dev/null 2>&1; then
      continue
    fi
    if command -v dnf >/dev/null 2>&1; then
      dnf -y update
      dnf install -y epel-release
      dnf install -y "$package"
    elif command -v yum >/dev/null 2>&1; then
      yum -y update
      yum install -y epel-release
      yum install -y "$package"
    elif command -v apt >/dev/null 2>&1; then
      apt update -y
      apt install -y "$package"
    elif command -v apk >/dev/null 2>&1; then
      apk update
      apk add "$package"
    elif command -v pacman >/dev/null 2>&1; then
      pacman -Syu --noconfirm
      pacman -S --noconfirm "$package"
    elif command -v zypper >/dev/null 2>&1; then
      zypper refresh
      zypper install -y "$package"
    else
      echo "未知的包管理器，无法安装: $package"
      return 1
    fi
  done
}

install_add_docker_cn() {
  local country
  country=$(curl -s --max-time 5 ipinfo.io/country 2>/dev/null)
  if [ "$country" = "CN" ]; then
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<'EOC'
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.m.ixdev.cn",
    "https://hub.rat.dev",
    "https://dockerproxy.net",
    "https://docker-registry.nmqu.com",
    "https://docker.amingg.com",
    "https://docker.hlmirror.com",
    "https://hub1.nat.tf",
    "https://hub2.nat.tf",
    "https://hub3.nat.tf",
    "https://docker.m.daocloud.io",
    "https://docker.kejilion.pro",
    "https://docker.367231.xyz",
    "https://hub.1panel.dev",
    "https://dockerproxy.cool",
    "https://docker.apiba.cn",
    "https://proxy.vvvv.ee"
  ]
}
EOC
  fi

  service_enable docker
  service_start docker
  service_restart docker
}

linuxmirrors_install_docker() {
  local country
  country=$(curl -s --max-time 5 ipinfo.io/country 2>/dev/null)
  if [ "$country" = "CN" ]; then
    bash <(curl -sSL https://linuxmirrors.cn/docker.sh) \
      --source mirrors.huaweicloud.com/docker-ce \
      --source-registry docker.1ms.run \
      --protocol https \
      --use-intranet-source false \
      --install-latest true \
      --close-firewall false \
      --ignore-backup-tips
  else
    bash <(curl -sSL https://linuxmirrors.cn/docker.sh) \
      --source download.docker.com \
      --source-registry registry.hub.docker.com \
      --protocol https \
      --use-intranet-source false \
      --install-latest true \
      --close-firewall false \
      --ignore-backup-tips
  fi

  install_add_docker_cn
}

ensure_docker_compose() {
  if docker compose version >/dev/null 2>&1 || docker-compose --version >/dev/null 2>&1; then
    return 0
  fi

  if command -v apt >/dev/null 2>&1; then
    apt update -y
    apt install -y docker-compose-plugin || apt install -y docker-compose
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y docker-compose-plugin || dnf install -y docker-compose
  elif command -v yum >/dev/null 2>&1; then
    yum install -y docker-compose-plugin || yum install -y docker-compose
  else
    install_pkg docker-compose
  fi
}

install_add_docker() {
  echo "正在安装 docker 环境..."
  if command -v apt >/dev/null 2>&1 || command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
    linuxmirrors_install_docker
  else
    install_pkg docker docker-compose
    install_add_docker_cn
  fi

  ensure_docker_compose

  echo "安装完成，版本信息："
  docker -v 2>/dev/null || true
  docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || true
}

show_default_net_if() {
  local default_net_if
  default_net_if=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
  if [ -n "$default_net_if" ]; then
    echo "当前默认出口网卡: $default_net_if"
  else
    echo "未检测到默认出口网卡，可手动执行: ip route get 1.1.1.1"
  fi
}

setup_xboard_forward() {
  echo "正在执行 xboard 端口转发设置..."

  # 清除防火墙
  /bin/systemctl stop firewalld.service >/dev/null 2>&1 || true
  /bin/systemctl disable firewalld.service >/dev/null 2>&1 || true
  setenforce 0 >/dev/null 2>&1 || true
  ufw disable >/dev/null 2>&1 || true
  iptables -P INPUT ACCEPT >/dev/null 2>&1 || true
  iptables -P FORWARD ACCEPT >/dev/null 2>&1 || true
  iptables -P OUTPUT ACCEPT >/dev/null 2>&1 || true
  iptables -t mangle -F >/dev/null 2>&1 || true
  iptables -F >/dev/null 2>&1 || true
  iptables -X >/dev/null 2>&1 || true

  # xboard 端口转发（避免重复追加）
  if ! iptables -t nat -C PREROUTING -p udp --dport 50000:65535 -j DNAT --to-destination :8899 >/dev/null 2>&1; then
    iptables -t nat -A PREROUTING -p udp --dport 50000:65535 -j DNAT --to-destination :8899
  fi

  # 规则持久化：未安装 netfilter-persistent 时自动安装
  if ! command -v netfilter-persistent >/dev/null 2>&1; then
    echo "检测到 netfilter-persistent 未安装，正在安装..."
    if command -v apt >/dev/null 2>&1; then
      export DEBIAN_FRONTEND=noninteractive
      apt update -y
      apt install -y netfilter-persistent iptables-persistent
    else
      install_pkg netfilter-persistent
    fi
  fi

  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1
  fi

  echo "xboard 端口转发设置已完成。"
}

show_zsz_menu() {
  while true; do
    clear
    echo "================ zsz 工具菜单 ================"
    echo "1. 执行 init_zsh_setup 主流程"
    echo "2. 安装/更新 Docker 与 Docker Compose"
    echo "3. 输出默认出口网卡"
    echo "4. xboard 端口转发设置"
    echo "0. 退出"
    echo "=============================================="
    read -r -p "请输入你的选择: " sub_choice

    case "$sub_choice" in
      1)
        bash "$INIT_SCRIPT_PATH"
        ;;
      2)
        install_add_docker
        ;;
      3)
        show_default_net_if
        ;;
      4)
        setup_xboard_forward
        ;;
      0)
        exit 0
        ;;
      *)
        echo "无效选择，请重新输入。"
        ;;
    esac

    read -r -p "按回车键返回菜单..." _
  done
}

show_zsz_menu
EOF

escaped_script_path=$(printf '%s\n' "$SCRIPT_SELF_PATH" | sed 's/[\/&]/\\&/g')
sed -i "s/__INIT_SCRIPT_PATH__/${escaped_script_path}/g" /usr/local/bin/zsz
chmod +x /usr/local/bin/zsz

echo -e "${GREEN}已安装 zsz 菜单命令，输入 ${YELLOW}zsz${GREEN} 即可调出选项。${NC}"
