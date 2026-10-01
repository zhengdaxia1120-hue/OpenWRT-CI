#!/bin/bash
# 预置 OpenClash Smart 内核 (aarch64 / AX3600)

CORE_DIR="./package/base-files/files/etc/openclash/core"
mkdir -p "$CORE_DIR"

# Smart 内核下载地址（官方）
CORE_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/smart/clash-linux-arm64.tar.gz"

echo "Downloading OpenClash Smart core for arm64..."
curl -L --retry 3 --connect-timeout 30 -o /tmp/clash-core.tar.gz "$CORE_URL" || {
  echo "Download failed, trying mirror..."
  curl -L --retry 3 -o /tmp/clash-core.tar.gz \
    "https://cdn.jsdelivr.net/gh/vernesong/OpenClash@core/master/smart/clash-linux-arm64.tar.gz"
}

if [ -f /tmp/clash-core.tar.gz ]; then
  tar -xzf /tmp/clash-core.tar.gz -C /tmp
  if [ -f /tmp/clash ]; then
    mv /tmp/clash "$CORE_DIR/clash_meta"
    chmod +x "$CORE_DIR/clash_meta"
    echo "OpenClash Smart core pre-installed successfully!"
  else
    echo "Extract failed: clash binary not found"
  fi
  rm -f /tmp/clash-core.tar.gz /tmp/clash
else
  echo "Failed to download OpenClash Smart core"
fi
