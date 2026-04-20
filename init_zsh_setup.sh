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
    
    # 1. 修改 root 密码（参考 kejilion.sh 的用户密码登录模式，使用 passwd 交互设置）
    if ! id root >/dev/null 2>&1; then
      echo "错误：用户 root 不存在"
      exit 1
    fi
    passwd root
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
