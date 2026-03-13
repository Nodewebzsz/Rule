#!/bin/bash

# ==============================================================================
# init_zsh_setup.sh (同时兼容 Debian / Ubuntu)
# 该脚本用于自动化配置 zsh、oh-my-zsh 及相关主题、插件
# 并在 Ubuntu 24.04 及以上版本自动开启 root 密码登录
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

# ================= 开启 root 密码登录 (仅限 Ubuntu >= 24.04) =================
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" = "ubuntu" ]; then
        # 使用 awk 判断版本号是否大于等于 24.04
        if awk "BEGIN {exit !($VERSION_ID >= 24.04)}"; then
            echo "================ 检测到 Ubuntu 版本为 $VERSION_ID，正在配置 Root 密码登录 ================"
            
            # 1. 修改 root 密码（增加交互式输入）
            read -r -p "请输入新的 root 密码 [直接回车默认为: zszxc123@]: " user_root_pwd
            user_root_pwd=${user_root_pwd:-zszxc123@}
            
            echo "root:$user_root_pwd" | chpasswd
            echo "root 密码已修改成功！"
            
            # 2. 配置 SSH 允许 root 密码登录与键盘交互式认证
            mkdir -p /etc/ssh/sshd_config.d
            # 写入 drop-in 配置确保优先级最高 (Ubuntu 24.04 默认引用该目录)
            echo "PasswordAuthentication yes" > /etc/ssh/sshd_config.d/99-allow-root-pass.conf
            echo "PermitRootLogin yes" >> /etc/ssh/sshd_config.d/99-allow-root-pass.conf
            echo "KbdInteractiveAuthentication yes" >> /etc/ssh/sshd_config.d/99-allow-root-pass.conf
            
            # 替换主配置（兼容和稳妥起见）
            sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
            sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
            sed -i 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/g' /etc/ssh/sshd_config
            
            # 3. 重启 SSH 服务生效
            systemctl restart ssh || systemctl restart sshd
            echo "SSH 服务已重启，已允许 root 密码登录 (包含 KbdInteractiveAuthentication)！"
            echo "================================================================================"
        fi
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

# 2.4.2 安装插件
echo "安装 fasd 和 fzf..."
# 某些 Debian 版本源中可能没有 fasd 或 fzf，失败则只输出提示不中断流程
apt -y install fasd fzf || echo "警告: fasd 或 fzf 安装失败，可能是您的系统源中不包含该包，不影响整体流程..."

echo "克隆 zsh-autosuggestions 和 zsh-syntax-highlighting 插件..."
# 获取 oh-my-zsh 的 custom 目录
ZSH_CUSTOM=${ZSH_CUSTOM:-/root/.oh-my-zsh/custom}
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting

echo "修改 /root/.zshrc 文件中的 plugins 配置..."
# 使用单行精确替换默认的 plugins=(git)，避开多行替换在某些 sed 版本上的兼容性问题
sed -i 's/^plugins=(git)/plugins=(git extract fasd fzf zsh-autosuggestions zsh-syntax-highlighting)/' /root/.zshrc

echo "添加快捷 alias 配置..."
cat << 'EOF' >> /root/.zshrc

# 自定义 aliases
alias vzsh="vim ~/.zshrc"
alias szsh="source ~/.zshrc"
alias czsh="cat ~/.zshrc"

# 初始化并全局注册 fasd 的所有快捷映射（如 z=fasd_cd -d）
eval "$(fasd --init auto)"
EOF

# 使之生效：在当前 bash 会话中，只能提醒用户，因为 source ~/.zshrc 需要在 zsh 中运行
echo "================================================================"
echo "配置已全部完成！"
echo ""
echo "🔥【必备插件指南】🔥"
echo "1. zsh-autosuggestions: 打字时若出现灰色的历史纪录建议，直接按【向右方向键 →】即可补全整行！"
echo "2. fzf (必须掌握): 此乃模糊搜索神器。随时按下【Ctrl + R】，会弹出一个交互菜单，输入部分命令字母就能极速找到以前敲过的任意长命令，回车即可加载到输入区跳过繁复打字！"
echo "3. fasd: 智能目录跳转。在终端输入【z 关键字】即可根据您的历史访问习惯瞬间跳到目标目录（比如输入 z log，它就能猜出你想去 /var/log 并跳转）。"
echo ""
echo "为使配置生效，请重新登录vps，或者直接在命令行中输入以下命令："
echo "zsh"
echo "进去后可以体验全新的界面了！"
echo "================================================================"
