#!/usr/bin/env bash

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="${PROJECT_NAME:-oci-helper-docker}"
BASE_DIR="${PWD}/${PROJECT_NAME}"
DATA_DIR="${BASE_DIR}/data"
KEYS_DIR="${DATA_DIR}/keys"
APP_YML="${DATA_DIR}/application.yml"
DB_FILE="${DATA_DIR}/oci-helper.db"
UPDATE_FLAG="${DATA_DIR}/update_version_trigger.flag"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
TARGET_SCRIPT="${BASE_DIR}/oci-helper-install.sh"

APPLICATION_YML_URL="${APPLICATION_YML_URL:-https://github.com/Yohann0617/oci-helper/releases/download/deploy/application.yml}"
DB_FILE_URL="${DB_FILE_URL:-https://github.com/Yohann0617/oci-helper/releases/download/deploy/oci-helper.db}"

print_step() {
  printf '\n==> %s\n' "$1"
}

warn() {
  printf '警告: %s\n' "$1"
}

require_any_command() {
  for command_name in "$@"; do
    if command -v "${command_name}" >/dev/null 2>&1; then
      return
    fi
  done

  echo "缺少命令，至少需要以下之一: $*"
  exit 1
}

ensure_dir_layout() {
  mkdir -p "${KEYS_DIR}"
  rm -f "${UPDATE_FLAG}"
  touch "${UPDATE_FLAG}"
}

write_compose_file() {
  cat > "${COMPOSE_FILE}" <<'EOF'
services:
  oci-helper:
    image: ghcr.io/yohann0617/oci-helper:master
    container_name: oci-helper
    restart: always
    ports:
      - "8818:8818"
    volumes:
      - ./data/application.yml:/app/oci-helper/application.yml
      - ./data/oci-helper.db:/app/oci-helper/oci-helper.db
      - ./data/keys:/app/oci-helper/keys
      - ./data/update_version_trigger.flag:/app/oci-helper/update_version_trigger.flag
    networks:
      - oci-helper-net

  websockify:
    image: ghcr.io/yohann0617/oci-helper-websockify:master
    container_name: oci-helper-websockify
    restart: always
    depends_on:
      - oci-helper
    ports:
      - "6080:6080"
    networks:
      - oci-helper-net

networks:
  oci-helper-net:
    driver: bridge
EOF
}

copy_project_files() {
  write_compose_file
  cp "${SOURCE_DIR}/oci-helper-install.sh" "${TARGET_SCRIPT}"
  chmod +x "${TARGET_SCRIPT}"
}

download_file() {
  local url="$1"
  local output="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${url}" -o "${output}"
    return
  fi

  wget -qO "${output}" "${url}"
}

download_required_files() {
  print_step "下载 application.yml"
  download_file "${APPLICATION_YML_URL}" "${APP_YML}"

  print_step "下载 oci-helper.db"
  download_file "${DB_FILE_URL}" "${DB_FILE}"
}

prompt_existing_directory_action() {
  if [[ ! -d "${BASE_DIR}" ]]; then
    EXISTING_ACTION="all"
    return
  fi

  if [[ -z "$(ls -A "${BASE_DIR}" 2>/dev/null)" ]]; then
    EXISTING_ACTION="all"
    return
  fi

  warn "目标目录已存在: ${BASE_DIR}"

  if [[ ! -t 0 ]]; then
    warn "当前不是交互式终端，默认跳过覆盖与重新下载。"
    EXISTING_ACTION="skip"
    return
  fi

  cat <<'EOF'
请选择操作：
1) 覆盖 compose，并重新下载文件
2) 仅覆盖 compose
3) 仅重新下载文件
4) 跳过已有内容
5) 退出
EOF

  while true; do
    read -r -p "请输入选项 [1-5]: " choice
    case "${choice}" in
      1)
        EXISTING_ACTION="all"
        return
        ;;
      2)
        EXISTING_ACTION="compose"
        return
        ;;
      3)
        EXISTING_ACTION="download"
        return
        ;;
      4)
        EXISTING_ACTION="skip"
        return
        ;;
      5)
        echo "已取消。"
        exit 0
        ;;
      *)
        echo "无效选项，请输入 1-5。"
        ;;
    esac
  done
}

apply_existing_directory_action() {
  case "${EXISTING_ACTION}" in
    all)
      copy_project_files
      download_required_files
      ;;
    compose)
      print_step "覆盖 docker-compose.yml 与 oci-helper-install.sh"
      copy_project_files
      ;;
    download)
      download_required_files
      ;;
    skip)
      print_step "跳过已有内容"
      ;;
    *)
      echo "未知操作: ${EXISTING_ACTION}"
      exit 1
      ;;
  esac
}

show_tree() {
  cat <<EOF
目录结构：
${BASE_DIR}/
├── docker-compose.yml
├── oci-helper-install.sh
└── data
    ├── application.yml
    ├── oci-helper.db
    ├── update_version_trigger.flag
    └── keys/
EOF
}

main() {
  print_step "检查依赖"
  require_any_command curl wget

  prompt_existing_directory_action

  print_step "创建目录与占位文件"
  ensure_dir_layout
  apply_existing_directory_action

  print_step "初始化完成"
  show_tree
  cat <<EOF

常用命令：
- 编辑配置: ${APP_YML}
- 启动服务: docker compose -f "${COMPOSE_FILE}" up -d
- 查看日志: docker compose -f "${COMPOSE_FILE}" logs -f oci-helper
EOF
}

main "$@"
