#!/usr/bin/env bash
# =============================================================================
# decision-os  /  Step 1: サーバー初期セットアップ
# 対象OS: Ubuntu 24.04 LTS
# 実行方法: bash 01_server_setup.sh
# =============================================================================
set -euo pipefail

# ---------- カラー出力ヘルパー ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }
section() { echo -e "\n${BOLD}========== $* ==========${RESET}"; }

# ---------- Ubuntu 24.04 チェック ----------
section "OS チェック"
. /etc/os-release
if [[ "$ID" != "ubuntu" || "$VERSION_ID" != "24.04" ]]; then
  warn "Ubuntu 24.04 LTS 以外の環境です: $PRETTY_NAME"
  read -rp "続行しますか？ [y/N]: " yn
  [[ "$yn" =~ ^[Yy]$ ]] || error "中断しました"
fi
success "OS: $PRETTY_NAME"

# ---------- 1. システム更新 ----------
section "1. システム更新"
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y \
  curl wget git build-essential ca-certificates gnupg lsb-release \
  make unzip jq libssl-dev libbz2-dev libreadline-dev libsqlite3-dev \
  libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
  libffi-dev liblzma-dev
success "システム更新・基本パッケージ インストール完了"

# ---------- 2. Docker CE ----------
section "2. Docker CE インストール"
if command -v docker &>/dev/null; then
  success "Docker は既にインストール済み: $(docker --version)"
else
  # 古いパッケージを削除
  sudo apt remove -y docker docker.io containerd runc 2>/dev/null || true

  # GPGキー追加
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  # リポジトリ追加
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt update -y
  sudo apt install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  success "Docker インストール完了: $(docker --version)"
fi

# dockerグループへの追加
if ! groups "$USER" | grep -q docker; then
  sudo usermod -aG docker "$USER"
  warn "dockerグループに追加しました。このスクリプト完了後に"
  warn "  newgrp docker  または  一度ログアウト→再ログイン  が必要です"
else
  success "dockerグループ: 設定済み"
fi

# ---------- 3. nvm / Node.js 20 LTS ----------
section "3. Node.js 20 LTS インストール（nvm）"
export NVM_DIR="$HOME/.nvm"

if [[ -d "$NVM_DIR" ]]; then
  success "nvm は既にインストール済み"
else
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  success "nvm インストール完了"
fi

# nvm をこのシェルセッションで有効化
# shellcheck disable=SC1090
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

if nvm ls 20 &>/dev/null; then
  success "Node.js 20 は既にインストール済み: $(node --version)"
else
  nvm install 20
  nvm use 20
  nvm alias default 20
  success "Node.js インストール完了: $(node --version)"
fi

# ---------- 4. pyenv / Python 3.12 ----------
section "4. Python 3.12 インストール（pyenv）"
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"

if [[ -d "$PYENV_ROOT" ]]; then
  success "pyenv は既にインストール済み"
else
  curl https://pyenv.run | bash
  success "pyenv インストール完了"
fi

eval "$(pyenv init -)"

if pyenv versions | grep -q "3.12"; then
  success "Python 3.12 は既にインストール済み: $(python --version)"
else
  info "Python 3.12.3 をビルド中（数分かかります）..."
  pyenv install 3.12.3
  pyenv global 3.12.3
  success "Python インストール完了: $(python --version)"
fi

# ---------- 5. ~/.bashrc への自動設定追記 ----------
section "5. シェル設定（~/.bashrc）への追記"

BASHRC="$HOME/.bashrc"

append_if_missing() {
  local marker="$1"
  local block="$2"
  if ! grep -qF "$marker" "$BASHRC"; then
    echo -e "\n$block" >> "$BASHRC"
    info "追記しました: $marker"
  else
    info "設定済みのためスキップ: $marker"
  fi
}

append_if_missing "nvm.sh" \
'# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"'

append_if_missing "PYENV_ROOT" \
'# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"'

success "~/.bashrc 設定完了"

# ---------- 完了メッセージ ----------
section "Step 1 完了"
echo -e "${GREEN}"
echo "  ✔ apt パッケージ"
echo "  ✔ Docker CE + Docker Compose v2"
echo "  ✔ Node.js 20 LTS（nvm）"
echo "  ✔ Python 3.12（pyenv）"
echo -e "${RESET}"
echo -e "${YELLOW}【次のアクション】${RESET}"
echo "  1. 以下のコマンドでdockerグループを有効化してください:"
echo -e "     ${BOLD}newgrp docker${RESET}"
echo "  2. その後 Step 2 を実行してください:"
echo -e "     ${BOLD}bash 02_project_setup.sh${RESET}"
