# MSL Next

MSL Next là kế hoạch xây một Linux subsystem cấp độ WSL + WSLg cho Mac Apple Silicon. Mục tiêu là giữ Linux terminal làm luồng tương tác chính, đồng thời cho phép ứng dụng Linux X11/Wayland xuất hiện như cửa sổ macOS riêng và chạy Linux user-space `amd64` trong distro ARM64 bằng Rosetta 2 khi Apple hỗ trợ.

Nhánh này đang ở giai đoạn kiến trúc và lập kế hoạch. Chưa có runtime thế hệ mới để cài đặt hoặc sử dụng. Implementation MVP trước đây được bảo toàn trong [`legacy/`](legacy/README.md); không bị xóa hoặc viết lại lịch sử.

## Phạm vi

- Chỉ hỗ trợ Mac Apple Silicon; không phát triển cho Intel Mac.
- CLI `msl` và daemon `msld` quản lý install, run, exec, stop, config, import/export và health.
- MSL Settings chỉ dùng để cài đặt, cấu hình và chẩn đoán; shell/TUI tiếp tục chạy trong Terminal.
- MSLg system image cung cấp Weston, XWayland, PipeWire, app discovery và per-window host integration.
- MSL Native Runtime dùng Apple Containerization + Virtualization.framework cho persistent VM, graphical devices và Rosetta directory share.
- Apple Container vẫn là đường Core Preview/OCI; QEMU/HVF chỉ còn compatibility và migration.

“WSL/WSLg-class” ở đây là tương thích về trải nghiệm và capability, không phải binary/API compatibility với `wsl.exe`, VHDX, Windows registry hoặc DirectX.

## Kiến trúc đích

```text
Terminal / msl CLI       MSL Settings       Linux GUI windows
         \                    |                    /
                    per-user msld
                           |
              versioned RuntimeBackend
                 /                    \
    Apple Container             MSL Native Runtime
     Core Preview          Containerization + Virtualization
                                      |
                         ARM64 user distro + read-only MSLg image
                                      |
                        Weston / XWayland / PipeWire / Rosetta
```

MSL Native Runtime là đích dài hạn cho full profile. User distro và MSLg system image được gắn trong cùng ARM64 VM; system image read-only có thể nâng cấp/rollback độc lập với dữ liệu distro. Rosetta chỉ dịch executable Linux x86_64 ở user space, không boot kernel hoặc distro x86_64.

## Lộ trình

Roadmap đầy đủ, performance budget, compatibility matrix, risk register và Definition of Done nằm tại [`plans/20260825002456-wsl-class-macos-roadmap.md`](plans/20260825002456-wsl-class-macos-roadmap.md).

Thứ tự triển khai đã chốt:

1. Contract, benchmark và spike graphical/Rosetta.
2. Shared core, CLI `msl` và daemon `msld`.
3. Golden Ubuntu và terminal Core Preview.
4. MSL Native Runtime cùng persistent Rosetta.
5. Terminal, workspace và localhost integration.
6. MSLg system image và per-window macOS bridge.
7. MSL Settings production, signing và update pipeline.
8. Portability, device và ecosystem.
9. GA hardening, soak test và release rollback.

Mỗi phase có exit gate. Không bắt đầu implementation WSLg/Rosetta production trước khi Phase 0 chứng minh graphical transport và Rosetta API bằng public Apple frameworks trên máy Apple Silicon thật.

## Cấu trúc repository

```text
.
├── README.md          # định hướng của nhánh next
├── plans/             # roadmap và quyết định phát triển
└── legacy/            # snapshot MVP cũ: SwiftUI, Apple Container và QEMU/HVF
```

- `main`: snapshot MVP ổn định trước khi tách kiến trúc.
- `next`: nhánh phát triển MSL thế hệ mới và là nguồn của tài liệu này.
- `legacy/`: frozen compatibility baseline; chỉ nhận sửa lỗi bảo toàn dữ liệu, bảo mật hoặc migration cần thiết.

Khi code thế hệ mới được triển khai, các module `CLI/`, `Daemon/`, `Runtime/`, `Host/`, `Guest/` và test tương ứng sẽ được tạo ở root theo boundary trong roadmap. Không phát triển tính năng mới trực tiếp trong `legacy/`.

## Kiểm tra MVP legacy

Chạy từ root của nhánh `next`:

```bash
make -C legacy lint
make -C legacy test
```

Hướng dẫn, giới hạn và cách build app cũ nằm trong [`legacy/README.md`](legacy/README.md).

## Nguồn kiến trúc

- [Apple Container](https://github.com/apple/container)
- [Apple Containerization](https://github.com/apple/containerization)
- [Apple Virtualization framework](https://developer.apple.com/documentation/virtualization)
- [Apple: Running Intel binaries in Linux VMs](https://developer.apple.com/documentation/virtualization/running-intel-binaries-in-linux-vms)
- [Microsoft WSLg architecture](https://github.com/microsoft/wslg)
