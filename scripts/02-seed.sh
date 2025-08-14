#!/usr/bin/env bash
set -euo pipefail

# 02-seed.sh: Prepare Subiquity autoinstall seed with per-build password
# Outputs:
#  - autoinstall/user-data (with hashed password)
#  - autoinstall/meta-data
#  - artifacts/password.txt (plaintext, for local testing only)

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Please run as root (sudo)" >&2
  exit 1
fi

mkdir -p autoinstall artifacts autoinstall/netplan

# Generate password (simple default). Override with PW or PASSWORD env var.
PW=${PW:-${PASSWORD:-P@ssword1!}}
HASH=$(mkpasswd -m sha-512 "$PW" 2>/dev/null || openssl passwd -6 "$PW")

# Emit plaintext for testers (never commit)
printf "%s\n" "$PW" > artifacts/password.txt
chmod 600 artifacts/password.txt

echo "Password set for user 'ubuntu': $PW (also saved to artifacts/password.txt)"

# Write meta-data (minimal)
cat > autoinstall/meta-data <<'EOF'
instance-id: micro-linux
local-hostname: micro
EOF

# Networking toggle (DHCP by default). For static, set NET_MODE=static and export IFACE/ADDR/PREFIX/GATEWAY
NET_MODE=${NET_MODE:-dhcp}
IFACE=${IFACE:-eth0}
ADDR=${ADDR:-192.168.1.10}
PREFIX=${PREFIX:-24}
GATEWAY=${GATEWAY:-192.168.1.1}

# Prepare netplan file
if [[ "$NET_MODE" == "static" ]]; then
  sed -e "s#\${IFACE}#$IFACE#g" \
      -e "s#\${ADDR}#$ADDR#g" \
      -e "s#\${PREFIX}#$PREFIX#g" \
      -e "s#\${GATEWAY}#$GATEWAY#g" \
      autoinstall/netplan/01-static.template.yaml > autoinstall/netplan/01-netcfg.yaml
else
  cp autoinstall/netplan/01-dhcp.yaml autoinstall/netplan/01-netcfg.yaml
fi


# Choose user-data template (override with USER_DATA_TEMPLATE)
# Allow forcing an automatic layout template for sanity checks
if [[ "${STORAGE_MODE:-}" == "auto" ]]; then
  USER_DATA_TEMPLATE=${USER_DATA_TEMPLATE:-autoinstall/user-data.autolayout.template}
else
  USER_DATA_TEMPLATE=${USER_DATA_TEMPLATE:-autoinstall/user-data.template}
fi
if [[ ! -f "$USER_DATA_TEMPLATE" ]]; then
  echo "ERROR: user-data template not found: $USER_DATA_TEMPLATE" >&2
  exit 2
fi
# Render user-data from template to avoid YAML indentation issues
sed "s#__PASSWORD_HASH__#${HASH}#" "$USER_DATA_TEMPLATE" > autoinstall/user-data

echo "Autoinstall seed written to autoinstall/user-data and autoinstall/meta-data"

# Optional: validate syntax with cloud-init schema
if command -v cloud-init >/dev/null 2>&1; then
  echo "Validating autoinstall user-data with cloud-init schema..."
  if cloud-init schema --config-file autoinstall/user-data >/dev/null; then
    echo "cloud-init schema validation: OK"
  else
    echo "cloud-init schema validation: FAILED" >&2
  fi
else
  echo "cloud-init not installed on host; skipping schema validation" >&2
fi
