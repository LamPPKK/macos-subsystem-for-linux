# MSL for Apple Silicon

Một Linux terminal/development environment chạy trên Mac Apple Silicon, lấy ý tưởng từ proof-of-concept [macos-subsystem-for-linux](https://github.com/LamPPKK/macos-subsystem-for-linux) nhưng được đóng gói thành stack có thể sử dụng hằng ngày.

Stack có hai backend và một app cấu hình native:

- **Apple Container machine (ưu tiên):** môi trường Linux persistent dựa trên OCI image, dùng `container machine` trên Apple Silicon + macOS 26.
- **QEMU/HVF (tương thích):** Debian 13 ARM64 cho macOS cũ hơn hoặc các VM qcow2 đã tạo bằng `msl-arm`.
- **MSL Settings:** app SwiftUI kiểu WSL Settings để tạo environment, chỉnh CPU/RAM/home mount, start/stop, xem log và mở login shell trong Terminal.

App chỉ làm nhiệm vụ cấu hình/quản lý. Toàn bộ tương tác Linux hằng ngày vẫn nằm trong Terminal.

## Bắt đầu với Apple Container

Apple Container cần Mac Apple Silicon và macOS 26 trở lên. Cài signed package từ [Apple Container releases](https://github.com/apple/container/releases), sau đó:

```bash
container system start
make app-bundle
open "dist/MSL-Settings-macOS.zip"
```

Trong MSL Settings, chọn **New environment**, giữ Ubuntu systemd image mặc định hoặc nhập OCI image có `/sbin/init`, rồi bấm **Open Terminal**. Lần đầu dùng preset Ubuntu, app tự build image từ Containerfile đi kèm. App gọi `container machine run`, vì vậy machine đang tắt sẽ được boot trước khi login shell mở.

Muốn Ubuntu 24.04 có systemd và bộ công cụ development cơ bản:

```bash
make machine-image
```

Sau đó tạo environment với image `local/msl-ubuntu-machine:24.04`.

Chi tiết backend, mapping command và giới hạn hiện tại nằm tại [docs/apple-container.md](docs/apple-container.md).

## Backend QEMU/HVF

`msl-arm` vẫn được giữ nguyên cho luồng Debian ARM64 qua QEMU/HVF.

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

`make test` chạy cả integration test Bash của QEMU backend và unit test Swift cho Apple Container command mapping, JSON parsing, validation và legacy compatibility. Build riêng app bằng `make app-build`; đóng gói `.app` ad-hoc signed trong ZIP bằng `make app-bundle`.

## Phạm vi hiện tại

- Apple Container backend hỗ trợ machine persistent, OCI image, CPU, RAM, macOS home mount, nested virtualization, custom kernel, default machine, log và Terminal login.
- QEMU backend hỗ trợ Debian 13 ARM64, serial console và SSH như trước.
- MSL Settings là control plane, không nhúng Linux desktop. Linux shell và ứng dụng TUI/CLI chạy trong Terminal.
- Apple Container và QEMU dùng hai kho disk riêng; app không tự convert hoặc xóa qcow2.
- `container machine` hiện không có setting đổi disk size, nên app chỉ hiển thị dung lượng do runtime quản lý.

Chi tiết lựa chọn kỹ thuật nằm trong [docs/design.md](docs/design.md).

## Kế hoạch phát triển

Roadmap để đưa MSL từ MVP hiện tại thành một Linux subsystem cấp độ WSL — gồm daemon, CLI thống nhất, performance budget, workspace/network integration, release pipeline và các phase gate — nằm tại [plans/20260825002456-wsl-class-macos-roadmap.md](plans/20260825002456-wsl-class-macos-roadmap.md).

## Nguồn kỹ thuật

- [Apple Container](https://github.com/apple/container)
- [Apple Container machine guide](https://github.com/apple/container/blob/main/docs/container-machine.md)
- [Apple Virtualization framework](https://developer.apple.com/documentation/virtualization)
- [QEMU Arm system emulator](https://www.qemu.org/docs/master/system/target-arm.html)
- [QEMU `virt` machine](https://www.qemu.org/docs/master/system/arm/virt.html)
- [QEMU AArch64 UEFI descriptor](https://github.com/qemu/qemu/blob/master/pc-bios/descriptors/60-edk2-aarch64.json)
- [Debian ARM64 cloud/QEMU notes](https://wiki.debian.org/Arm64Qemu)
- [Debian cloud image guidance](https://wiki.debian.org/Cloud/)
