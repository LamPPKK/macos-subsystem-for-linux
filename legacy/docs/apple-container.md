# Apple Container và MSL Settings

## Kiến trúc

MSL Settings là control plane native bằng SwiftUI. App không tự hiện thực hypervisor và không nhúng terminal. Nó gọi CLI bằng `Process` với mảng argument riêng biệt, đọc JSON chính thức, sau đó mở một login shell trong Terminal.

```text
MSL Settings
├── Apple Container (ưu tiên, macOS 26+)
│   └── container machine -> persistent Linux VM -> login shell
└── msl-arm (fallback)
    └── QEMU + HVF -> Debian qcow2 -> SSH/serial
```

Apple Container chạy Linux container trong lightweight VM riêng, dùng OCI-compatible image và package Containerization của Apple. `container machine` bổ sung vòng đời persistent giống một Linux distribution trong WSL: filesystem sống qua stop/start, user khớp host và home directory của macOS có thể mount vào guest.

## Yêu cầu

### Apple Container backend

- Mac Apple Silicon.
- macOS 26 trở lên.
- Bản Apple Container có nhóm lệnh `container machine`.
- Signed installer từ trang release chính thức của Apple Container.

Khởi động service lần đầu:

```bash
container system start
```

MSL Settings dùng `container system status --format json` để hiển thị health. Nút Start gọi `container system start --enable-kernel-install`, tránh prompt tương tác khi cần cài recommended kernel.

### QEMU fallback

Fallback dùng executable `msl-arm` được bundle trong app. QEMU và firmware vẫn phải được cài như hướng dẫn trong README. Backend này dành cho macOS cũ hơn hoặc VM qcow2 hiện hữu.

## Mapping hành động

| Hành động trong app | Apple Container command |
| --- | --- |
| Refresh | `container machine list --format json` |
| Xem chi tiết | `container machine inspect NAME` |
| Tạo | `container machine create --no-boot ... IMAGE` |
| Mở Terminal | `container machine run --name NAME` |
| Áp dụng CPU/RAM/home | `container machine set --name NAME key=value...` |
| Đặt default | `container machine set-default NAME` |
| Stop | `container machine stop NAME` |
| Logs | `container machine logs -n 120 NAME` |
| Delete | `container machine delete NAME` |

Thay đổi `machine set` có hiệu lực sau lần stop/start kế tiếp. `machine run` tự boot machine nếu đang tắt, nên app không cần tạo một lệnh start giả.

## Image machine

Một machine image phải có `/sbin/init` và đủ user-management tools để Apple Container provision tài khoản host. Preset mặc định của MSL Settings là:

```text
local/msl-ubuntu-machine:24.04
```

Repo và app bundle đều có `images/ubuntu-machine/Containerfile` để tạo Ubuntu 24.04 với systemd và các công cụ development cơ bản. App kiểm tra local image và tự build preset ở lần tạo đầu tiên; CLI có target tương đương:

```bash
make machine-image
container machine create \
  --name ubuntu \
  --cpus 4 \
  --memory 4G \
  --home-mount rw \
  local/msl-ubuntu-machine:24.04
```

Sau khi build, có thể chọn image đó ngay trong New environment của app.

## Home mount và quyền truy cập

Ba mode được expose đúng theo Apple Container:

- `rw`: Linux được đọc và ghi home của macOS.
- `ro`: chỉ đọc, phù hợp với build không cần sửa source từ guest.
- `none`: không đưa home của host vào machine.

App không chạy qua shell khi quản lý runtime. Tên machine được giới hạn thành letters, numbers, `.`, `_`, `-`; image không được chứa whitespace hoặc bắt đầu bằng `-`.

Khi mở Terminal, app tạo file `.command` tại:

```text
~/Library/Application Support/MSL Settings/Terminal/
```

Directory và script đều có permission `0700`; executable và từng argument được single-quote trước khi ghi. App không lưu password, registry token hay SSH private key.

## Build app

Build từ source cần full Xcode tại `/Applications/Xcode.app` vì test target dùng XCTest; Command Line Tools riêng lẻ không đủ. Nếu Xcode nằm ở vị trí khác, truyền `XCODE_DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer` cho Make.

```bash
make app-build
make app-bundle
open "dist/MSL-Settings-macOS.zip"
```

Bundle được ad-hoc sign để chạy local. App cố ý không bật App Sandbox vì cần gọi Apple Container, QEMU CLI và mở Terminal. Khi phân phối bên ngoài máy development, cần Developer ID signing và notarization riêng.

Packaging mặc định cross-build target `arm64-apple-macosx13.0`, kể cả khi build trên host Intel. Có thể override bằng `MSL_APP_TRIPLE` cho mục đích development; Apple Container runtime vẫn chỉ được hỗ trợ trên Apple Silicon.

Có thể override executable khi test hoặc dùng install tùy chỉnh:

```bash
MSL_CONTAINER_BIN=/custom/bin/container open "/Applications/MSL Settings.app"
MSL_ARM_BIN=/custom/bin/msl-arm open "/Applications/MSL Settings.app"
```

## Không tự migration disk

Apple Container quản lý machine storage riêng; QEMU backend dùng `~/.msl-arm/vms/*/disk.qcow2`. Hai format và lifecycle không giống nhau. MSL Settings không convert, mount hoặc xóa disk của backend khác để tránh làm mất dữ liệu.

`container machine set` hiện hỗ trợ CPU, memory, home mount, nested virtualization và custom kernel, nhưng chưa có setting đổi disk size. Vì vậy UI chỉ hiển thị dung lượng disk runtime báo về.
