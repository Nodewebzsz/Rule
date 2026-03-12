#!/bin/bash

# ==============================================================================
# ubuntu_zsh_setup.sh
# 该脚本用于在 Ubuntu 系统下自动化配置 zsh、oh-my-zsh 及相关主题、插件
# ==============================================================================

# 1. 要求在 root 权限下进行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本 (例如使用: sudo ./ubuntu_zsh_setup.sh)"
  exit 1
fi

# 切换到 root 根目录
cd /root || { echo "无法切换到 /root 目录"; exit 1; }
echo "当前目录: $(pwd)"

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
chsh -s /usr/bin/zsh

# 2.4 更改 oh-my-zsh 配置
echo "================ 2.4 修改 oh-my-zsh 配置 ================"

# 2.4.1 更换 ZSH 主题
echo "更换 ZSH 主题为 pygmalion..."
sed -i 's/^ZSH_THEME=".*"/ZSH_THEME="pygmalion"/' /root/.zshrc

# 2.4.2 安装插件
echo "安装 fasd..."
apt -y install fasd

echo "克隆 zsh-autosuggestions 和 zsh-syntax-highlighting 插件..."
# 获取 oh-my-zsh 的 custom 目录
ZSH_CUSTOM=${ZSH_CUSTOM:-/root/.oh-my-zsh/custom}
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting

echo "修改 /root/.zshrc 文件中的 plugins 配置..."
# 使用 sed 替换掉默认的多行或单行 plugins 配置
sed -i -e '/^plugins=(/,/)/c\
plugins=(\n\
  git extract fasd zsh-autosuggestions zsh-syntax-highlighting\n\
)' /root/.zshrc

echo "添加快捷 alias 配置..."
cat << 'EOF' >> /root/.zshrc

# 自定义 aliases
alias vzsh="vim ~/.zshrc"
alias szsh="source ~/.zshrc"
alias czsh="cat ~/.zshrc"
EOF

# 使之生效：在当前 bash 会话中，只能提醒用户，因为 source ~/.zshrc 需要在 zsh 中运行
echo "================================================================"
echo "配置已全部完成！"
echo "为使配置生效，请重新登录，或者直接在命令行中输入以下命令："
echo "zsh"
echo "进去后可以体验全新的界面了！"
echo "================================================================"
