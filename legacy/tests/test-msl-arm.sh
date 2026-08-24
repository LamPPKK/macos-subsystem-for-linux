#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

PROJECT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
CLI="$PROJECT_DIRECTORY/bin/msl-arm"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/msl-arm-test.XXXXXX")
SHORT_TMP_ROOT=$(mktemp -d "/tmp/msl-arm-dl.XXXXXX")
TEST_HOME="$TMP_ROOT/state"
FIXTURES="$TMP_ROOT/fixtures"
FAKE_BIN="$TMP_ROOT/bin"

cleanup() {
  rm -rf "$TMP_ROOT" "$SHORT_TMP_ROOT"
}
trap cleanup EXIT INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_contains() {
  local file_or_text="$1"
  local expected="$2"
  local content

  if [[ -f "$file_or_text" ]]; then
    content=$(<"$file_or_text")
  else
    content="$file_or_text"
  fi
  [[ "$content" == *"$expected"* ]] ||
    fail "expected '$expected' in: $content"
}

file_mode() {
  if stat -f '%Lp' "$1" >/dev/null 2>&1; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

mkdir -p "$FIXTURES/firmware" "$FAKE_BIN"
printf 'base qcow2 fixture\n' >"$FIXTURES/base.qcow2"
ssh-keygen -q -t ed25519 -N '' -C 'msl-arm-test' -f "$FIXTURES/id_ed25519"
TEST_PUBLIC_KEY=$(awk '{ print $1 " " $2 }' "$FIXTURES/id_ed25519.pub")
printf 'firmware code\n' >"$FIXTURES/firmware/edk2-aarch64-code.fd"
printf 'firmware vars\n' >"$FIXTURES/firmware/edk2-arm-vars.fd"

cat >"$FAKE_BIN/qemu-img" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --version) printf 'qemu-img version test\n' ;;
  resize) printf '%s\n' "$*" >>"${QEMU_IMG_LOG:?}" ;;
  *) exit 0 ;;
esac
EOF

cat >"$FAKE_BIN/qemu-system-aarch64" <<'EOF'
#!/usr/bin/env bash
printf 'qemu-system-aarch64 test stub\n'
EOF

cat >"$FAKE_BIN/hdiutil" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=""
while (($# > 0)); do
  if [[ "$1" == "-o" ]]; then
    output="$2"
    shift 2
  else
    shift
  fi
done
[[ -n "$output" ]]
printf 'CIDATA fixture\n' >"$output"
EOF

chmod +x "$FAKE_BIN/qemu-img" "$FAKE_BIN/qemu-system-aarch64" "$FAKE_BIN/hdiutil"

export PATH="$FAKE_BIN:$PATH"
export QEMU_FIRMWARE_DIR="$FIXTURES/firmware"
export QEMU_IMG_LOG="$TMP_ROOT/qemu-img.log"
export MSL_ARM_SKIP_HOST_CHECK=1

"$CLI" --home "$TEST_HOME" init dev \
  --cpus 6 \
  --memory 6144 \
  --disk 50G \
  --ssh-port 4222 \
  --user builder \
  --identity "$FIXTURES/id_ed25519" \
  --image "$FIXTURES/base.qcow2"

VM_DIRECTORY="$TEST_HOME/vms/dev"
assert_file "$VM_DIRECTORY/config"
assert_file "$VM_DIRECTORY/disk.qcow2"
assert_file "$VM_DIRECTORY/efi-vars.fd"
assert_file "$VM_DIRECTORY/seed.iso"
assert_file "$VM_DIRECTORY/cloud-init/meta-data"
assert_file "$VM_DIRECTORY/cloud-init/user-data"
[[ "$(file_mode "$VM_DIRECTORY")" == "700" ]] || fail "VM directory must be mode 700"
[[ "$(file_mode "$VM_DIRECTORY/config")" == "600" ]] || fail "config must be mode 600"
[[ "$(file_mode "$VM_DIRECTORY/disk.qcow2")" == "600" ]] || fail "disk must be mode 600"

assert_contains "$VM_DIRECTORY/config" "CPUS=6"
assert_contains "$VM_DIRECTORY/config" "MEMORY_MB=6144"
assert_contains "$VM_DIRECTORY/config" "SSH_PORT=4222"
assert_contains "$VM_DIRECTORY/config" "GUEST_USER=builder"
assert_contains "$VM_DIRECTORY/cloud-init/user-data" "name: 'builder'"
assert_contains "$VM_DIRECTORY/cloud-init/user-data" "console=tty0 console=ttyAMA0,115200n8"
assert_contains "$VM_DIRECTORY/cloud-init/user-data" "$TEST_PUBLIC_KEY"
assert_contains "$TMP_ROOT/qemu-img.log" "resize"
assert_contains "$TMP_ROOT/qemu-img.log" "50G"

if command -v ruby >/dev/null 2>&1; then
  ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' "$VM_DIRECTORY/cloud-init/user-data"
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  REAL_SEED="$TMP_ROOT/real-seed.iso"
  /usr/bin/hdiutil makehybrid \
    -o "$REAL_SEED" \
    "$VM_DIRECTORY/cloud-init" \
    -iso \
    -joliet \
    -iso-volume-name cidata \
    -joliet-volume-name cidata \
    >/dev/null
  REAL_SEED_INFO=$(/usr/bin/file "$REAL_SEED")
  assert_contains "$REAL_SEED_INFO" "ISO 9660"
  assert_contains "$REAL_SEED_INFO" "CIDATA"
fi

QEMU_COMMAND=$("$CLI" --home "$TEST_HOME" command dev)
assert_contains "$QEMU_COMMAND" "virt\\,accel=hvf\\,highmem=on"
assert_contains "$QEMU_COMMAND" "-cpu host"
assert_contains "$QEMU_COMMAND" "hostfwd=tcp:127.0.0.1:4222-:22"
assert_contains "$QEMU_COMMAND" "seed.iso"
assert_contains "$QEMU_COMMAND" "-nographic"

LIST_OUTPUT=$("$CLI" --home "$TEST_HOME" list)
assert_contains "$LIST_OUTPUT" "dev"
assert_contains "$LIST_OUTPUT" "stopped"

CONFIG_OUTPUT=$("$CLI" --home "$TEST_HOME" config dev)
assert_contains "$CONFIG_OUTPUT" "DISK_SIZE=50G"

printf 'downloaded image fixture\n' >"$FIXTURES/remote.qcow2"
export REMOTE_IMAGE_FIXTURE="$FIXTURES/remote.qcow2"
export REMOTE_IMAGE_HASH
REMOTE_IMAGE_HASH=$(/usr/bin/shasum -a 512 "$REMOTE_IMAGE_FIXTURE" | awk '{print $1}')

cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=""
url=""
while (($# > 0)); do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    http*) url="$1"; shift ;;
    *) shift ;;
  esac
done
[[ -n "$output" && -n "$url" ]]
if [[ "$url" == */SHA512SUMS ]]; then
  printf '%s  debian-13-generic-arm64.qcow2\n' "${REMOTE_IMAGE_HASH:?}" >"$output"
else
  cp "${REMOTE_IMAGE_FIXTURE:?}" "$output"
fi
EOF
chmod +x "$FAKE_BIN/curl"

DOWNLOAD_HOME="$SHORT_TMP_ROOT/state"
"$CLI" --home "$DOWNLOAD_HOME" init downloaded \
  --identity "$FIXTURES/id_ed25519"
assert_file "$DOWNLOAD_HOME/cache/debian-13-generic-arm64.qcow2"
assert_file "$DOWNLOAD_HOME/cache/SHA512SUMS"
assert_file "$DOWNLOAD_HOME/vms/downloaded/disk.qcow2"

if "$CLI" --home "$TEST_HOME" init dev \
  --identity "$FIXTURES/id_ed25519" \
  --image "$FIXTURES/base.qcow2" >/dev/null 2>&1; then
  fail "duplicate VM creation should fail"
fi

if "$CLI" --home "$TEST_HOME" init bad-port \
  --ssh-port 70000 \
  --identity "$FIXTURES/id_ed25519" \
  --image "$FIXTURES/base.qcow2" >/dev/null 2>&1; then
  fail "invalid SSH port should fail"
fi

if "$CLI" --home "$TEST_HOME" init overflow \
  --cpus 18446744073709551615 \
  --memory 18446744073709552128 \
  --identity "$FIXTURES/id_ed25519" \
  --image "$FIXTURES/base.qcow2" >/dev/null 2>&1; then
  fail "overflowing CPU/memory values should fail"
fi

if "$CLI" --home "$TEST_HOME" init bad-user \
  --user root \
  --identity "$FIXTURES/id_ed25519" \
  --image "$FIXTURES/base.qcow2" >/dev/null 2>&1; then
  fail "reserved root user should fail"
fi

ssh-keygen -q -t ed25519 -N '' -C 'msl-arm-other' -f "$FIXTURES/other_id"
cp "$FIXTURES/other_id.pub" "$FIXTURES/id_ed25519.pub"
if "$CLI" --home "$TEST_HOME" init bad-key \
  --identity "$FIXTURES/id_ed25519" \
  --image "$FIXTURES/base.qcow2" >/dev/null 2>&1; then
  fail "mismatched SSH key pair should fail"
fi

printf 'PASS: msl-arm CLI integration tests\n'
