#!/usr/bin/env bash
# 配置 multica daemon 开机自动启动（systemd 用户服务）
# 适用：已安装 multica CLI 的 Linux 机器
# 用法：bash setup-multica-daemon.sh（用 ubuntu/普通用户执行，不要用 root）

set -euo pipefail

MULTICA_BIN=$(command -v multica 2>/dev/null || echo "")
if [ -z "$MULTICA_BIN" ]; then
  echo "错误：未找到 multica 命令，请先安装 multica CLI"
  exit 1
fi

# su - 切换过来时没有完整登录会话，手动补上 D-Bus 和运行时目录
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

if [ ! -d "$XDG_RUNTIME_DIR" ]; then
  echo "错误：$XDG_RUNTIME_DIR 不存在，请确保 systemd-logind 正在运行"
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

# 如果 daemon 已在 systemd 外手动运行，先停掉再交给 systemd 接管
if $MULTICA_BIN daemon status 2>/dev/null | grep -q "running"; then
  echo "检测到 daemon 已在运行，先停止再由 systemd 接管..."
  $MULTICA_BIN daemon stop 2>/dev/null || true
  sleep 1
fi

# enable-linger 让 daemon 在未登录时也能随系统启动
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
