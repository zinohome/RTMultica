#!/usr/bin/env bash
# 配置 multica daemon 开机自动启动（systemd 用户服务）
# 适用：已安装 multica CLI 的 Linux 机器
# 用法：bash setup-multica-daemon.sh

set -euo pipefail

MULTICA_BIN=$(command -v multica 2>/dev/null || echo "")
if [ -z "$MULTICA_BIN" ]; then
  echo "错误：未找到 multica 命令，请先安装 multica CLI"
  exit 1
fi

SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/multica-daemon.service"

mkdir -p "$SERVICE_DIR"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Multica Agent Runtime Daemon
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$MULTICA_BIN daemon start --foreground
ExecStop=$MULTICA_BIN daemon stop
Restart=on-failure
RestartSec=5s
Environment=HOME=$HOME

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable multica-daemon.service

# enable-linger 需要 sudo，让 daemon 在未登录时也能随系统启动
if sudo loginctl enable-linger "$USER" 2>/dev/null; then
  echo "Linger 已开启（无需登录即可自动启动）"
else
  echo "警告：enable-linger 需要 sudo 权限，请手动执行："
  echo "  sudo loginctl enable-linger $USER"
fi

# 如果 daemon 当前未运行，立即启动
if ! systemctl --user is-active --quiet multica-daemon.service; then
  systemctl --user start multica-daemon.service
fi

echo ""
echo "完成！multica daemon 已配置为开机自启。"
echo ""
echo "常用命令："
echo "  systemctl --user status multica-daemon    # 查看状态"
echo "  systemctl --user restart multica-daemon   # 重启"
echo "  journalctl --user -u multica-daemon -f    # 实时日志"
