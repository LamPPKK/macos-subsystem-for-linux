# msl-arm

Một Linux terminal/development environment chạy trên Mac Apple Silicon, lấy ý tưởng từ proof-of-concept [macos-subsystem-for-linux](https://github.com/LamPPKK/macos-subsystem-for-linux) nhưng được đóng gói thành CLI có thể sử dụng lại.

`msl-arm` chạy Debian 13 ARM64 bằng QEMU, Apple Hypervisor Framework (HVF) và UEFI. Lệnh `init` dùng Debian cloud image nên không phải cài hệ điều hành thủ công: cloud-init tạo user, cài SSH key, mở serial console và nới filesystem theo dung lượng disk đã chọn.

## Yêu cầu

- Mac Apple Silicon (`arm64`), chạy Terminal native, không chạy shell qua Rosetta.
- macOS có Hypervisor Framework.
- Homebrew và QEMU:

```bash
brew install qemu
```

Kiểm tra máy trước khi tạo VM:

```bash
./bin/msl-arm doctor
```

## Bắt đầu nhanh

```bash
# Tạo VM tên "dev" (4 CPU, 4 GiB RAM, disk 40 GiB)
./bin/msl-arm init dev

# Chạy nền
./bin/msl-arm start dev --detach

# Lần boot đầu cloud-init có thể cần khoảng 1-2 phút
./bin/msl-arm ssh dev

# Tắt máy an toàn
./bin/msl-arm stop dev
```

Lần đầu `init`, tool sẽ:

1. tải Debian 13 `generic-arm64.qcow2` từ máy chủ chính thức;
2. xác minh SHA-512 từ manifest của Debian;
3. tạo SSH key riêng tại `~/.msl-arm/keys/id_ed25519` nếu chưa có;
4. tạo disk, UEFI variable store và cloud-init seed;
5. chỉ forward SSH vào `127.0.0.1`, không public VM ra mạng LAN.

## Cấu hình VM

```bash
./bin/msl-arm init buildbox \
  --cpus 8 \
  --memory 8192 \
  --disk 80G \
  --ssh-port 4023 \
  --user lam
```

Dùng SSH identity có sẵn:

```bash
./bin/msl-arm init dev --identity ~/.ssh/id_ed25519
```

`PATH.pub` phải tồn tại. Tool chỉ đưa public key vào guest; private key không được sao chép.

Dùng image ARM64 đã tải sẵn để bỏ qua download:

```bash
./bin/msl-arm init dev --image /path/to/debian-13-generic-arm64.qcow2
```

## Các lệnh

| Lệnh | Tác dụng |
| --- | --- |
| `doctor` | Kiểm tra macOS ARM64, HVF, QEMU, UEFI firmware và công cụ hệ thống |
| `init [NAME]` | Tạo VM mới và cloud-init seed |
| `start [NAME]` | Chạy VM trong terminal hiện tại |
| `start [NAME] --detach` | Chạy VM nền |
| `console [NAME]` | Gắn vào serial console của VM chạy nền; `Control-C` chỉ detach |
| `ssh [NAME]` | SSH vào guest |
| `ssh [NAME] -- COMMAND` | Chạy một lệnh trong guest |
| `stop [NAME]` | Gửi yêu cầu shutdown qua QEMU monitor |
| `status [NAME]` | Xem trạng thái VM |
| `list` | Liệt kê VM |
| `command [NAME]` | In đầy đủ lệnh QEMU, hữu ích khi debug |
| `config [NAME]` | In cấu hình VM |

Nếu không ghi `NAME`, tên mặc định là `debian`.

## Console và SSH

Chạy trực tiếp trong terminal:

```bash
./bin/msl-arm start dev
```

Trong chế độ này, phím thoát của QEMU là `Control-A`, sau đó `X`.

Chạy nền và attach console:

```bash
./bin/msl-arm start dev --detach
./bin/msl-arm console dev
```

SSH dùng NAT user-mode của QEMU:

```text
127.0.0.1:<SSH_PORT> -> guest:22
```

Host key được lưu riêng cho từng VM, không sửa `~/.ssh/known_hosts`.

CLI đặt `umask 077`; disk, cấu hình, SSH key và QEMU control socket chỉ owner truy cập được.

## Dữ liệu

Mặc định tất cả state nằm ngoài repo:

```text
~/.msl-arm/
├── cache/                  # Debian base image + checksum manifest
├── keys/                   # SSH identity riêng của msl-arm
└── vms/<name>/
    ├── cloud-init/
    ├── config
    ├── disk.qcow2
    ├── efi-vars.fd
    ├── seed.iso
    └── known_hosts
```

Đổi vị trí bằng `--home DIR` hoặc `MSL_ARM_HOME`:

```bash
./bin/msl-arm --home /Volumes/VMs/msl-arm init dev
```

## Cài CLI vào PATH

```bash
make install
# mặc định: ~/.local/bin/msl-arm
```

Hoặc đặt prefix khác:

```bash
make install PREFIX=/opt/homebrew
```

## Kiểm thử

```bash
make test
make lint
```

Test suite tạo image/firmware/QEMU giả trong thư mục tạm để kiểm tra luồng `init`, config, cloud-init và lệnh QEMU mà không boot VM thật.

## Phạm vi bản MVP

- Chỉ hỗ trợ host Mac Apple Silicon và guest Debian 13 ARM64.
- Chỉ cung cấp terminal/SSH; chưa có desktop GUI, folder sharing, snapshot hay suspend/resume.
- Base image được giữ trong cache, nhưng mỗi VM có disk độc lập để xóa cache không làm hỏng VM.

Chi tiết lựa chọn kỹ thuật nằm trong [docs/design.md](docs/design.md).

## Nguồn kỹ thuật

- [QEMU Arm system emulator](https://www.qemu.org/docs/master/system/target-arm.html)
- [QEMU `virt` machine](https://www.qemu.org/docs/master/system/arm/virt.html)
- [QEMU AArch64 UEFI descriptor](https://github.com/qemu/qemu/blob/master/pc-bios/descriptors/60-edk2-aarch64.json)
- [Debian ARM64 cloud/QEMU notes](https://wiki.debian.org/Arm64Qemu)
- [Debian cloud image guidance](https://wiki.debian.org/Cloud/)
