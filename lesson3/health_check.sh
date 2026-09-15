#!/bin/bash
# Kiểm tra trạng thái các dịch vụ, in cảnh báo đỏ nếu dịch vụ chết.

services=("nginx" "ssh") # ponytail: RHEL/CentOS dùng "sshd" thay cho "ssh"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

for svc in "${services[@]}"; do
  if systemctl is-active --quiet "$svc"; then
    echo -e "${GREEN}[OK]${NC} $svc is running"
  else
    echo -e "${RED}[ALERT] $svc is DOWN!${NC}"
  fi
done
