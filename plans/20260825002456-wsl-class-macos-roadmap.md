# Kế hoạch MSL: Linux subsystem cấp độ WSL + WSLg cho macOS ARM

- Trạng thái: Proposed
- Ngày: 2026-08-25
- Đối tượng: maintainer, contributor và người kiểm thử MSL
- Phạm vi mục tiêu: chỉ Mac Apple Silicon; terminal, Linux GUI và linux/amd64 qua Rosetta 2

## Tóm tắt quyết định

MSL sẽ trở thành một Linux subsystem được quản lý, không phải một ứng dụng VM truyền thống. Người dùng cài một lần, gọi `msl` từ Terminal để vào distro mặc định, chạy ứng dụng Linux GUI như ứng dụng macOS và dùng Rosetta 2 khi cần chạy binary Linux `amd64` trong distro ARM64.

Kiến trúc được khuyến nghị:

1. Chỉ hỗ trợ Apple Silicon. Không dành ngân sách phát triển cho Intel Mac hoặc x86 host.
2. Dùng Apple Container Machine làm backend sớm cho terminal/distro lifecycle trên macOS 26 trở lên.
3. Xây MSL Native Runtime trên Apple Containerization + Virtualization.framework cho các capability Apple Container Machine chưa expose: system distro kiểu WSLg, custom virtio channel và Rosetta trong distro persistent.
4. Thêm một daemon theo user là `msld` làm control plane duy nhất cho CLI, GUI và graphical sessions.
5. Xây CLI `msl` với mental model gần WSL: install, list, run, exec, stop, shutdown, set-default, config, export, import, mount, gui và doctor.
6. Xây `MSLg` system distro read-only gồm Weston, XWayland và PipeWire; ánh xạ từng cửa sổ Linux thành cửa sổ macOS, kèm clipboard, audio, input, HiDPI và app discovery.
7. Tích hợp Rosetta 2 theo hai tầng: workload OCI `amd64` bằng Apple Container ngay khi có thể, sau đó binary `amd64` bên trong distro ARM64 bằng `VZLinuxRosettaDirectoryShare` và `binfmt_misc`.
8. Giữ QEMU/HVF chỉ để đọc/chạy VM cũ và migration; không yêu cầu parity WSLg/Rosetta trên backend này.

Không fork toàn bộ WSLg hoặc tự viết hypervisor. MSL tái sử dụng Weston/XWayland/FreeRDP/PipeWire ở guest và framework ảo hóa của Apple; phần riêng của MSL là control plane, guest contract và host integration native macOS.

## Bối cảnh và bằng chứng

### Hệ thống hiện có trong repo

Các điểm dưới đây đã được xác nhận trực tiếp từ source hiện tại:

- `msl-arm` tạo Debian ARM64 VM bằng QEMU/HVF, cloud-init, UEFI, qcow2 và SSH/serial.
- MSL Settings là app SwiftUI, gọi Apple Container và `msl-arm` bằng `Process`, rồi mở shell trong Terminal.
- Apple Container client hiện hỗ trợ service status, list/inspect/create/set/default/stop/delete/logs và machine run.
- Preset Ubuntu 24.04 có systemd đã có trong `images/ubuntu-machine/Containerfile`.
- GUI và CLI chưa chia sẻ một daemon hoặc persistent API; mỗi frontend tự gọi runtime.
- Apple Container mới chỉ được unit-test bằng mock trên host hiện tại; chưa có CI chạy runtime thật trên Apple Silicon + macOS 26.
- Bundle hiện chỉ ad-hoc signed, chưa có Developer ID signing, notarization hoặc update channel.

### Điều học từ WSL 2

WSL 2 đạt trải nghiệm tốt nhờ che giấu VM phía sau một control plane: dùng Linux kernel thật trong lightweight managed VM, boot nhanh, footprint nhỏ, systemd và full syscall compatibility. Microsoft cũng chỉ rõ file I/O xuyên biên giới host/guest là điểm yếu, và khuyên đặt project trên filesystem cùng phía với tool thực thi.

MSL nên sao chép mental model này, không sao chép implementation Windows:

- VM là chi tiết nội bộ, không buộc người dùng quản trị firmware, port SSH hay process QEMU.
- Một lệnh mặc định mở distro mặc định.
- Distro có lifecycle, config, export/import và trạng thái thống nhất.
- Linux kernel và systemd được runtime quản lý.
- Host integration phải tiện, nhưng workspace hiệu năng cao cần nằm trên Linux filesystem.

WSLg đạt trải nghiệm GUI liền mạch bằng một system distro tách khỏi user distro. System distro chạy Weston, XWayland và audio server; socket được project vào user distro. Weston dùng RDP backend/RAIL để remote từng cửa sổ thay vì cả desktop, còn host plugin phụ trách app list, icon, clipboard, audio và window lifecycle. MSL sẽ giữ boundary system-distro/user-distro này nhưng thay thành phần host Windows bằng client native AppKit/Metal/CoreAudio trên macOS.

### Điều Apple đã cung cấp

Apple Container chạy OCI image trong lightweight Linux VM, tối ưu cho Apple silicon. Container Machine bổ sung đúng các primitive gần WSL: machine persistent, init system, user khớp host, home sharing, boot-on-run, nhiều distro, CPU/RAM config và lifecycle command. Containerization phía dưới đã có Virtualization.framework, ext4, optimized kernel, networking, guest control qua vsock và Rosetta cho OCI workload `amd64`.

Virtualization.framework hỗ trợ chạy binary Linux x86_64 trong ARM Linux bằng `VZLinuxRosettaDirectoryShare`; guest mount Rosetta share rồi đăng ký interpreter qua `binfmt_misc`. Apple nói rõ đây không phải cơ chế boot một distro/kernel Intel. Trên macOS 26 trở xuống có bước cài Rosetta; tài liệu hiện tại cho biết macOS 27 tích hợp trực tiếp Intel translation cho Linux app.

Apple Container CLI hiện expose `--rosetta` cho container workload nhưng chưa expose Rosetta cho Container Machine persistent. Một issue upstream năm 2026 vẫn tái hiện `amd64` Container Machine thất bại với `Exec format error`. Vì WSLg và machine-wide Rosetta đều cần quyền cấu hình VM/device sâu hơn, MSL Native Runtime trở thành workstream bắt buộc; nó tái sử dụng Containerization/Virtualization.framework thay vì viết hypervisor từ đầu.

## Product promise

V1 phải tạo được trải nghiệm sau:

- Sau khi hoàn tất installer, người dùng mở Terminal và gọi `msl` để vào Ubuntu mặc định.
- Nếu distro đang tắt, MSL tự boot và đưa ra prompt mà không lộ bước quản trị VM.
- CLI và MSL Settings luôn thấy cùng state, cùng lỗi và cùng tiến trình operation.
- Distro giữ nguyên package, service và file qua restart.
- Project có thể chạy theo hai mode: shared workspace để tiện chỉnh sửa bằng app macOS, hoặc Linux-native workspace để tối đa I/O.
- App Linux X11 và Wayland xuất hiện thành cửa sổ macOS riêng, có Dock/Command-Tab, clipboard, audio, input method và HiDPI.
- Distro ARM64 có thể chạy binary Linux `amd64` bằng Rosetta 2 mà không cài một distro x86_64 riêng.
- Ứng dụng GUI và Rosetta có capability detection; khi host/runtime chưa hỗ trợ, UI fail rõ ràng thay vì fallback âm thầm sang emulation chậm.
- Stop, delete, update và import/export không được làm mất dữ liệu âm thầm.
- Khi runtime hỏng, `msl doctor` trả về nguyên nhân và hành động khắc phục cụ thể.

## Mục tiêu hiệu năng

Các giá trị sau là target cần được benchmark trên baseline M2, 16 GB RAM, SSD còn ít nhất 20% trống. Chúng chưa phải kết quả của implementation hiện tại.

| Luồng | Target v1 |
| --- | --- |
| CLI list/status qua daemon đang chạy | p95 không quá 150 ms |
| Exec trong distro đã boot | p50 không quá 300 ms, p95 không quá 600 ms |
| Cold boot đến interactive shell sau khi image đã có | p50 không quá 2 giây, p95 không quá 4 giây |
| Mở MSL Settings đến khi hiện cached state | không quá 500 ms |
| Daemon idle, không có distro chạy | không quá 150 MB resident memory |
| Distro đã stop | không giữ guest RAM |
| Operation UI dài | không block main thread; có progress và cancel khi runtime cho phép |
| GUI app đầu tiên khi graphical service đã warm | p50 không quá 1 giây, p95 không quá 2 giây |
| GUI app đầu tiên từ cold distro | p50 không quá 3 giây, p95 không quá 5 giây |
| Local GUI input-to-present | p95 không quá 50 ms với workload 2D chuẩn |
| Rosetta CLI workload sau warm-up | không chậm quá 2,5 lần so với binary ARM64 tương đương ở benchmark đã chọn |

Không được tối ưu bằng cách giữ tất cả distro chạy vĩnh viễn. Chính sách warm/idle phải có giới hạn rõ ràng và người dùng có thể tắt.

## Kiến trúc đích

### Frontend

- `msl`: CLI chính, ưu tiên startup nhanh và output ổn định cho người lẫn automation.
- MSL Settings: GUI native để install distro, cấu hình CPU/RAM/home, xem health/log, đặt default và quản lý storage.
- Terminal: data plane cho shell/TUI; app chỉ yêu cầu daemon mở phiên shell.
- MSLg Host: process native quản lý cửa sổ Linux, input, clipboard, audio, notification, app icon và lifecycle graphical session.

### Control plane `msld`

`msld` là LaunchAgent theo user và là process duy nhất được phép mutate runtime state. CLI và GUI giao tiếp bằng versioned XPC contract.

Trách nhiệm:

- serialize operation theo distro và deduplicate request trùng;
- cache list/status để UI hiển thị tức thì rồi refresh nền;
- quản lý install, boot, exec, stop, delete và default distro;
- phát progress/event cho nhiều client;
- quản lý idle timeout, crash recovery và operation journal;
- chuẩn hóa lỗi runtime thành error code ổn định;
- giữ capability matrix theo version Apple Container;
- quản lý port forwarding, hostname và workspace metadata thuộc MSL.

Daemon không giữ shell tương tác trong XPC. Nó cấp session request; CLI gắn stdin/stdout/TTY trực tiếp với runtime để tín hiệu, resize terminal và exit code đi xuyên suốt.

### Runtime adapter

`RuntimeBackend` trở thành protocol nội bộ với capability rõ ràng thay vì để UI gọi executable trực tiếp.

- Apple Container Machine: backend Core Preview/terminal và compatibility; không còn là mặc định cho distro mới sau khi MSL Native Runtime vượt production gate.
- MSL Native Runtime: backend production cho graphical session và persistent Rosetta, xây trên Apple Containerization + Virtualization.framework; không tự viết CPU emulator hay hypervisor.
- QEMU/HVF: read/launch compatibility cho VM hiện có; deprecate dần sau khi có migration an toàn và không nhận feature WSLg/Rosetta mới.

Mọi call đến CLI ngoài phải dùng argument array, tách stdout/stderr, timeout, cancellation và version probe. Không parse table nếu JSON/machine-readable format có sẵn.

### Chuyển đổi backend và bố trí system distro

Core Preview được phép tạo distro bằng Apple Container Machine để đưa terminal workflow đến người dùng sớm. Sau Phase 3, MSL Native Runtime trở thành mặc định cho distro mới thuộc full profile. Backend là metadata hiển thị công khai; MSL không tự đổi backend của distro đang chạy hoặc hứa dùng chung disk format giữa hai runtime.

Migration Apple Container → MSL Native Runtime là transaction copy-and-verify: quiesce guest, tạo archive/manifest/checksum, restore sang disk mới, boot compatibility suite, rồi mới cho người dùng chuyển default. Source distro được giữ nguyên cho đến khi người dùng xác nhận xóa. Nếu consistency primitive chưa đủ an toàn, distro cũ tiếp tục terminal-only thay vì nhận WSLg/Rosetta bằng workaround không bảo đảm dữ liệu.

Trên MSL Native Runtime, user distro và MSLg system image nằm trong cùng ARM64 VM để tránh thêm một lớp network/remoting giữa hai VM. System image là volume read-only, chạy service trong namespace riêng và chỉ project socket/metadata đã định nghĩa vào user environment. Một system image version có thể được cache dùng chung trên host, nhưng state/session của từng distro vẫn tách biệt.

### Guest contract

Default image là Ubuntu LTS có systemd và một gói guest integration nhỏ, versioned độc lập với app.

Guest integration phụ trách:

- readiness signal sau boot;
- chuẩn hóa user/default shell và environment;
- path/workspace metadata;
- service/port discovery tùy chọn;
- shutdown acknowledgement;
- version/capability report.
- mount/project socket từ MSLg system distro vào user distro;
- đăng ký Rosetta interpreter an toàn qua `binfmt_misc` khi capability được bật;
- app discovery từ desktop entry và icon metadata;
- session bus, locale, timezone, clipboard và GUI environment contract.

Apple Container backend chỉ dùng entrypoint công khai. MSL Native Runtime được phép dùng API public của Containerization/Virtualization.framework và virtio socket do chính MSL cấu hình; không dựa vào private framework hoặc copy Rosetta binary ra khỏi share do Apple quản lý.

## Ma trận tương thích WSL/WSLg mục tiêu

| Nhóm capability | Mục tiêu MSL trên Apple Silicon | Milestone |
| --- | --- | --- |
| Linux kernel thật, syscall compatibility | ARM64 Linux VM, systemd, cgroup v2 | Core GA |
| Distro lifecycle | install/list/default/run/exec/stop/shutdown/unregister | Core GA |
| Custom distro | OCI/rootfs import, signed catalog, default user | Core GA |
| Export/import | archive có quiesce, manifest, checksum và restore verification | Portability GA |
| Resource config | CPU, RAM, disk policy, idle shutdown, memory pressure | Core GA |
| File interop | shared macOS workspace + Linux-native high-performance workspace | Core GA |
| Path/command interop | cwd translation, `open`/clipboard helper, exit-code/signal parity | Integration GA |
| Network | localhost, stable hostname, IPv4/IPv6, DNS/proxy, explicit expose | Integration GA |
| systemd services | boot/shutdown đúng lifecycle; background policy rõ | Core GA |
| Linux GUI X11 | XWayland trong MSLg system distro, cửa sổ macOS riêng | MSLg GA |
| Linux GUI Wayland | Weston compositor, per-window remoting | MSLg GA |
| Audio/microphone | PipeWire bridge sang CoreAudio, permission theo app | MSLg GA |
| Clipboard/notification | NSPasteboard/UserNotifications bridge hai chiều | MSLg GA |
| App discovery | desktop entry thành launcher/Dock/Spotlight item có icon | MSLg GA |
| HiDPI/multi-display/input | scale, keyboard layout, IME, pointer, accessibility smoke | MSLg GA |
| GPU acceleration | capability spike; software/CPU rendering là fallback có cảnh báo | Post-beta gate |
| Linux `amd64` app | Rosetta 2 trong ARM64 distro, không boot x86 kernel | Rosetta GA |
| OCI `amd64` workload | Apple Container `--rosetta` lane | Core beta |
| Nested virtualization | M3+ và custom KVM kernel theo capability Apple | Advanced |
| USB/device attach | USB/IP hoặc VZ device API sau security/driver spike | Advanced |
| Full Linux desktop | optional desktop window; không thay per-app default | Advanced |

“Tương thích” ở đây là parity về user journey và capability. MSL không hứa binary/API compatibility với `wsl.exe`, VHDX, DirectX hoặc Windows registry.

## MSLg: Linux GUI trên macOS

### Guest graphical system distro

Mỗi user distro được ghép với một MSLg system image read-only, versioned cùng host app và gắn vào cùng VM. Nó chứa Weston, XWayland, PipeWire và MSLg agent. Socket Wayland/X11/audio được project vào user distro; người dùng không cài hoặc sửa system image. Update thay image và luôn có rollback một version.

Weston quản lý Wayland và XWayland. Backend remoting ưu tiên RDP RAIL/FreeRDP nếu spike xác nhận macOS client đạt per-window, clipboard và HiDPI requirements. Nếu upstream macOS client không đủ, MSL xây host bridge tối thiểu bằng AppKit/Metal quanh protocol đã chọn; full-desktop RDP/XQuartz chỉ là fallback phát triển, không phải Definition of Done.

### Host integration

- Mỗi Linux surface map thành một `NSWindow`; close/minimize/focus/resize đồng bộ hai chiều.
- `.desktop` và icon được agent gửi lên host; launcher gọi distro + app ID ổn định.
- Clipboard dùng MIME-aware bridge, giới hạn kích thước và yêu cầu consent cho file transfer.
- PipeWire audio map sang CoreAudio; microphone đi qua permission macOS và mặc định tắt.
- Keyboard layout, dead key, IME, pointer capture, multi-display và fractional scale có contract test riêng.
- Graphical session warm độc lập với user app và tự restart khi compositor crash; app user không được phép sửa system distro.

### GPU policy

WSLg trên Windows dùng vGPU/DirectX; macOS không cung cấp một API tương đương có thể mặc định coi là sẵn cho Linux guest. MSLg beta phải chạy đúng bằng software rendering trước. GPU/Metal acceleration chỉ ship sau spike chứng minh API public, license phù hợp, correctness và performance; không quảng cáo parity GPU trước khi có benchmark thật.

## Rosetta 2 trong Linux

### Contract hỗ trợ

- Host chỉ là Apple Silicon.
- Guest vẫn là ARM64 Linux; Rosetta dịch executable/user-space library x86_64.
- Không boot kernel/distro x86_64 và không dùng Rosetta cho kernel module.
- `msl exec --arch amd64` chọn Intel translation; `auto` đọc ELF architecture và chỉ dùng Rosetta khi cần.
- Distro config có `rosetta = auto|enabled|disabled`; default là `auto` sau khi người dùng đồng ý cài component Apple trên macOS 26 trở xuống.

### Hai giai đoạn

Giai đoạn A dùng Apple Container `container run --rosetta --arch amd64` cho OCI workload tạm thời. Đây là capability chính thức nhưng không cung cấp persistent machine semantics.

Giai đoạn B dùng MSL Native Runtime: host kiểm `VZLinuxRosettaDirectoryShare.availability`, yêu cầu Apple installer khi cần, attach share `virtiofs` vào ARM64 VM, guest mount read-only và đăng ký binary handler qua `binfmt_misc`. AOT cache dùng option public của Virtualization.framework khi có; cache có quota và bị xóa an toàn.

MSL không tải, bundle, copy hoặc chỉnh sửa Rosetta runtime. Nếu Apple đổi availability/license/API, capability bị disable với actionable error; distro ARM64 vẫn hoạt động bình thường.

## Distro, image và storage

### Distro model

Mỗi distro có ID ổn định, display name, runtime backend, image digest, lifecycle state, config, workspace mode và timestamps. Metadata MSL không được coi là source of truth duy nhất cho disk; daemon phải reconcile với runtime sau crash hoặc upgrade.

Ubuntu LTS là golden path. Debian và custom OCI image là supported-but-advanced sau khi vượt compatibility suite. Image catalog phải pin digest, có provenance/SBOM và update policy; không silently đổi base image của distro đang tồn tại.

### Hai workspace mode

Shared workspace ưu tiên tiện lợi: source nằm trên macOS và được share vào guest. Mode này phù hợp editor/IDE native và project không quá metadata-heavy.

Linux-native workspace ưu tiên tốc độ: source nằm trên persistent ext4 của distro. Host editor truy cập qua remote workflow hoặc sync có chủ đích. Đây là mode khuyến nghị cho package manager, monorepo, compiler và database workload nặng.

GUI phải giải thích tradeoff khi tạo distro. Benchmark phải đo git, package install, small-file scan, compile và database fsync trên cả hai mode; không quảng cáo mode nào “nhanh” nếu chưa có số liệu.

### Export, import và xóa

Apple Container Machine hiện chưa cung cấp product contract mà MSL có thể giả định cho snapshot/export đầy đủ. V1 chỉ ship export/import sau spike xác minh một trong hai đường:

- runtime-supported export có consistency guarantee; hoặc
- guest-coordinated archive với filesystem quiesce, manifest, checksum và restore test.

Delete luôn cần xác nhận chứa đúng tên distro. GUI/CLI hiển thị storage sẽ mất; option backup-before-delete phải thất bại đóng nếu export không thành công.

## Terminal, file và network integration

### Terminal

- `msl` không argument mở shell trong default distro.
- Có thể chọn distro, user, working directory hoặc chạy một command và trả nguyên exit code.
- Current macOS directory chỉ được translate nếu nằm trong share được phép; nếu không, shell mở ở Linux home và cảnh báo một lần.
- TTY resize, signals, Unicode, locale và clipboard paste phải có integration tests.
- GUI gọi cùng session API, không tạo contract thứ hai bằng file script lâu dài.

### Network

- NAT là mặc định, không cần root và không expose LAN.
- Distro có stable logical hostname thuộc namespace MSL; IP runtime không phải public contract.
- Port exposure phải là explicit mapping, bind loopback mặc định và phát hiện collision trước khi boot.
- Localhost forwarding tự động chỉ được bật cho port người dùng khai báo hoặc service được approve; không scan/expose mọi listening socket.
- Bridged networking là advanced capability, ngoài v1 nếu đòi privileged helper.

## Resource management để “mượt”

- Cache state trong daemon và trả stale-while-refresh cho read path.
- Boot theo nhu cầu; một distro vừa dùng có thể warm theo idle timeout, các distro khác dừng.
- Readiness dựa trên handshake/event, không sleep cố định hoặc poll dày.
- Pull/build image tách khỏi create transaction, có progress, resume và checksum.
- Operation cùng distro được coalesce; operation khác distro có concurrency limit dựa trên RAM host.
- Theo dõi macOS memory pressure; trước mắt stop idle distro theo policy. Memory balloon chỉ dùng khi backend công bố capability đáng tin cậy.
- UI dùng optimistic presentation cho setting local nhưng chỉ commit state sau runtime acknowledgement.
- Mọi performance regression quan trọng phải có benchmark artifact trước merge.

## Security, update và distribution

- App, daemon, CLI và guest artifacts phải có version compatibility matrix.
- Release public cần Developer ID signing, hardened runtime, notarization và Sparkle hoặc update channel tương đương có signature.
- Không thêm privileged helper trong v1. Nếu bridged network về sau cần quyền cao, helper phải có protocol tối thiểu và audit riêng.
- Registry credential nằm trong Keychain; không ghi token vào config/log.
- Image được pin digest và verify provenance trước first boot.
- Log redaction mặc định cho home path, token và environment secret.
- XPC chỉ nhận client cùng signing requirement trong production.
- State update dùng atomic replace và operation journal; crash giữa create/delete phải reconcile được.

## CLI contract đề xuất

Nhóm lệnh v1:

- `msl`: vào default distro.
- `msl install`: cài distro từ catalog hoặc OCI reference.
- `msl list`: liệt kê distro, state, backend và default.
- `msl run` và `msl exec`: mở interactive shell hoặc chạy command.
- `msl exec --arch arm64|amd64|auto`: chọn kiến trúc executable; `amd64` chỉ chạy khi Rosetta capability sẵn sàng.
- `msl gui`: liệt kê hoặc mở Linux GUI app qua MSLg session của distro.
- `msl mount`: quản lý workspace/share được cấp quyền, không tự động expose toàn bộ filesystem macOS.
- `msl stop`, `msl shutdown`: dừng một distro hoặc toàn bộ.
- `msl set-default`: đổi distro mặc định.
- `msl config`: đọc/ghi CPU, memory, workspace, idle timeout và exposed ports.
- `msl doctor`: kiểm host, Apple Container version, service, image và storage.
- `msl logs`: log daemon/runtime/guest theo lớp.

`export`, `import` và `unregister` chỉ chuyển từ experimental sang stable khi vượt data-integrity gate. Machine-readable output có schema version; human output có thể đổi nhưng không trộn warning vào stdout JSON.

## Các phase phát triển

### Phase 0 — Contract và benchmark baseline

Mục tiêu: khóa product semantics trước khi thay kiến trúc.

- Viết domain model distro, lifecycle state machine, error taxonomy và capability matrix.
- Chốt CLI UX, config precedence và XPC schema v1.
- Tạo benchmark harness cho list, warm exec, cold shell, shared/ext4 I/O và idle memory.
- Spike MSLg transport: kiểm chứng per-window remoting, clipboard, HiDPI và input bằng RDP RAIL/FreeRDP trên macOS; ghi rõ tiêu chí chuyển sang AppKit/Metal bridge tối thiểu nếu upstream không đạt.
- Spike persistent Rosetta: dựng ARM64 VM mẫu bằng API public, attach `VZLinuxRosettaDirectoryShare`, mount read-only và chạy executable x86_64 qua `binfmt_misc`.
- Ghi baseline trên ít nhất M1 8 GB, M2 16 GB và M3; dùng macOS 26 release hiện hành.

Exit gate: benchmark reproducible, lifecycle invariants được review, chọn được graphical transport, persistent Rosetta chạy được trên ít nhất một baseline và không còn câu hỏi chặn thiết kế daemon/runtime.

### Phase 1 — Shared core, CLI `msl` và daemon `msld`

Mục tiêu: một control plane cho mọi frontend.

- Tách domain/runtime code khỏi SwiftUI thành package dùng chung.
- Thêm LaunchAgent, versioned XPC, operation queue, event stream và recovery journal.
- Thêm CLI read path và interactive session path.
- Chuyển GUI từ direct `Process` sang XPC.

Exit gate: CLI và GUI luôn đồng bộ state; daemon restart giữa create/stop không làm hỏng distro; list đạt SLO.

### Phase 2 — Golden Ubuntu và Core Preview

Mục tiêu: install-to-shell một bước.

- Xuất bản Ubuntu LTS machine image được pin digest, systemd-ready và có guest integration.
- Thực hiện install, boot-on-run, exec, stop, default distro, config và logs qua Apple backend.
- Thêm image progress, retry/resume, version probe và actionable doctor.
- Bảo toàn QEMU VM hiện có ở compatibility view.

Exit gate: fresh machine đi từ installer đến shell không cần QEMU/Homebrew; cold/warm targets đạt trên baseline hoặc có accepted exception kèm số liệu; UI ghi rõ đây là terminal profile nếu backend chưa có WSLg/Rosetta persistent.

### Phase 3 — MSL Native Runtime và persistent Rosetta

Mục tiêu: có backend production do MSL kiểm soát đủ sâu cho graphical device và Intel translation, nhưng vẫn chỉ dùng framework public của Apple.

- Đóng gói Containerization/Virtualization.framework sau `RuntimeBackend`; không để frontend phụ thuộc API VM.
- Quản lý kernel, initrd, ext4, boot configuration, vsock/virtiofs, resource policy và lifecycle bằng manifest versioned.
- Attach Rosetta directory share khi config cho phép; guest mount read-only, đăng ký `binfmt_misc` và report capability về daemon.
- Thêm capability gate theo host OS, Rosetta availability và runtime version; ARM64 distro vẫn boot bình thường nếu Rosetta không sẵn sàng.
- Xác minh license boundary: không bundle, export hoặc copy Rosetta artifact; chỉ gọi installer/API do Apple cung cấp.
- Xây migration copy-and-verify từ Apple Container backend, có preflight dung lượng, checksum, compatibility boot và rollback về source distro.
- Chuyển default cho distro mới sang MSL Native Runtime chỉ sau khi lifecycle, recovery và migration gate cùng pass.

Exit gate: distro ARM64 persistent chạy được cùng một test workload ở bản ARM64 và x86_64; disable/unavailable path không làm hỏng distro; update runtime có rollback và không mất disk.

### Phase 4 — Terminal, workspace và localhost integration

Mục tiêu: developer workflow hằng ngày không có “VM friction”.

- Hoàn thiện TTY, signal, cwd/path translation và Terminal launch.
- Ship shared và Linux-native workspace modes.
- Thêm explicit port exposure, stable hostname và collision handling.
- Tài liệu remote editor cho Linux-native workspace.

Exit gate: compatibility suite cho shell phổ biến, benchmark filesystem công bố, service trong guest truy cập được qua localhost mapping sau restart.

### Phase 5 — MSLg system distro và per-window host bridge

Mục tiêu: Linux X11/Wayland app xuất hiện như app macOS riêng, không buộc người dùng mở cả Linux desktop.

- Build system distro read-only, reproducible và versioned chứa Weston, XWayland, PipeWire và MSLg agent.
- Project socket Wayland/X11/audio có kiểm soát vào user distro; app discovery đọc desktop entry/icon và gắn distro identity ổn định.
- Xây MSLg Host cho window lifecycle, Dock/Command-Tab, clipboard, CoreAudio/microphone, keyboard/IME, pointer và notifications.
- Ship software-rendering correctness baseline; giữ GPU/Metal acceleration sau capability spike và benchmark.
- Thêm health/restart/rollback cho compositor, audio service và system distro mà không đụng dữ liệu user distro.

Exit gate: bộ app GTK, Qt và Electron ở cả Wayland/X11 mở thành cửa sổ macOS riêng; clipboard/audio/input/HiDPI pass; compositor crash phục hồi mà không restart hoặc corrupt user distro.

### Phase 6 — GUI Settings production và release pipeline

Mục tiêu: MSL Settings đủ chất lượng phân phối.

- Onboarding, install/catalog, operation progress, storage view, diagnostics và destructive confirmations.
- Accessibility, keyboard navigation, localization foundation và crash reporting opt-in.
- Developer ID, notarization, signed update feed và rollback release.

Exit gate: app qua accessibility checklist, upgrade từ hai version trước giữ nguyên distro, Gatekeeper chấp nhận clean install.

### Phase 7 — Portability, device và ecosystem

Mục tiêu: import/export an toàn và nhiều distro.

- Hoàn tất export/import sau consistency spike.
- Thêm Debian và custom image validation profile.
- IDE hooks, dotfiles bootstrap và optional container engine inside distro.
- Đánh giá USB/device attach, nested virtualization trên chip hỗ trợ và optional full-desktop mode qua capability/security spike riêng.

Exit gate: restore test bit-for-bit ở scope đã cam kết, failure injection không làm mất source distro, custom image lỗi bị chặn trước create.

### Phase 8 — GA hardening

Mục tiêu: độ tin cậy đủ cho daily driver.

- Soak test nhiều ngày, memory/disk pressure, sleep/wake, network changes và abrupt reboot.
- Upgrade/downgrade matrix cho macOS, Apple Container, MSL và guest image.
- Soak graphical sessions nhiều cửa sổ/distro, compositor/audio crash và display hot-plug.
- Chạy Rosetta compatibility/performance matrix trên macOS 26 và các release mới hơn còn được hỗ trợ.
- Security review, threat model, recovery runbook và support bundle redaction.

Exit gate: không còn P0/P1, data-integrity suite pass, performance budget pass và release rollback đã diễn tập.

## Thay đổi dự kiến theo khu vực repo

| Khu vực | Hướng thay đổi |
| --- | --- |
| `App/MSLSettings` | Giữ SwiftUI; thay direct runtime client bằng XPC client và shared models |
| `App/MSLSettings/Sources/MSLControlCore` | Tách thành core package độc lập UI, thêm state machine và capability model |
| `Daemon/MSLD` | LaunchAgent, XPC service, operation journal, runtime orchestration |
| `CLI/MSL` | CLI nhanh, TTY/session handling, JSON schema |
| `Runtime/MSLNative` | Adapter Containerization/Virtualization.framework, persistent VM, virtio/vsock và Rosetta device configuration |
| `Host/MSLgHost` | AppKit/Metal window bridge, CoreAudio, clipboard, input, app discovery và graphical lifecycle |
| `Guest/MSLgSystem` | System distro read-only chứa Weston, XWayland, PipeWire và MSLg agent |
| `Guest` | user-distro integration, readiness, socket projection, `binfmt_misc`, app discovery và compatibility contract |
| `images` | reproducible user/system image build, pinned inputs, provenance, SBOM và rollback metadata |
| `tests` | contract, integration, graphical, Rosetta, failure injection, performance và upgrade matrix |
| `scripts`/release | signing, notarization, update feed và artifact verification |
| `bin/msl-arm` | compatibility backend; đóng băng feature sau migration tooling |

Tên thư mục mới là đề xuất và có thể đổi trong Phase 0, nhưng boundary frontend/core/daemon/runtime/guest là invariant kiến trúc.

## Validation strategy

### Mỗi pull request

- Swift unit tests, strict concurrency, shell lint và schema compatibility.
- Fake runtime contract tests cho mọi error/timeout/cancel path.
- Fake graphical/Rosetta capability tests, gồm host không hỗ trợ và partial failure.
- Data mutation tests phải chứng minh target path và atomicity.
- Benchmark smoke test với regression threshold rộng.

### CI Apple Silicon bắt buộc

- Self-hosted Mac Apple Silicon chạy macOS 26 và Apple Container release được pin.
- Install image, create, cold/warm exec, systemd service, stop/restart/delete.
- MSL Native Runtime boot, readiness, virtiofs/vsock và Rosetta share trên host thật.
- Shared workspace permissions, symlink, case sensitivity và large/small file workload.
- Network mapping, sleep/wake, service restart và daemon crash recovery.
- GUI suite với app GTK, Qt và Electron; Wayland/X11, nhiều cửa sổ/distro, clipboard, audio/microphone, HiDPI, multi-display, keyboard/IME và compositor crash recovery.
- Rosetta suite chạy workload ARM64/x86_64 tương đương, kiểm availability/install flow, disabled path và xác nhận artifact Apple không bị copy vào bundle/distro/export.
- Signed app install, first launch, update và rollback.

### Release gate

- Test trên M1/M2/M3-or-newer và host RAM 8/16/32 GB.
- Ít nhất 100 lifecycle loops mỗi baseline, 24 giờ soak và abrupt reboot recovery.
- Software rendering là correctness baseline bắt buộc; GPU acceleration có release gate và benchmark riêng, không được dùng để che failure ở fallback.
- MSLg system distro phải upgrade/rollback độc lập mà không đổi dữ liệu user distro.
- Export/import test nếu feature được bật.
- Không regression quá 10% ở p95 startup/exec so với release trước nếu không có waiver công khai.
- Support bundle đã kiểm redaction; không chứa token, private key hoặc nội dung file người dùng.

## Rủi ro và giảm thiểu

| Rủi ro | Giảm thiểu |
| --- | --- |
| Apple Container command/JSON thay đổi | Version probe, adapter theo release, contract fixtures và pin minimum/maximum đã test |
| Apple Container Machine không expose graphical device hoặc persistent Rosetta | Capability gate và MSL Native Runtime dùng Containerization/Virtualization.framework public; không phụ thuộc private API |
| RDP RAIL/FreeRDP phía macOS không đạt per-window semantics | Phase 0 spike có exit criteria; fallback thiết kế là AppKit/Metal host bridge tối thiểu, không hạ DoD xuống full desktop |
| Không có đường GPU Linux-to-Metal public đủ ổn định | Ship software-rendering baseline; chỉ bật acceleration sau security, license, correctness và performance gate |
| Rosetta availability, license hoặc API đổi theo macOS | Probe runtime, yêu cầu Apple installer khi phù hợp, không redistribute artifact và giữ ARM64 distro hoạt động khi capability tắt |
| MSLg system distro upgrade làm hỏng GUI | Image read-only, pin version theo host, health check trước switch và rollback một version |
| Shared home chậm với workload nhiều file | Hai workspace mode, benchmark công khai, Linux-native là recommendation cho workload nặng |
| First pull/build lâu | Prebuilt signed image, progress/resume, background prefetch sau consent |
| Runtime thiếu snapshot/export | Không giả lập vội; capability gate và guest-coordinated consistency spike |
| Daemon trở thành single point of failure | Journal, idempotent operations, reconcile runtime on launch và crash injection tests |
| Xóa nhầm persistent storage | Typed destructive API, exact-name confirmation, backup gate và không dùng broad path deletion |
| App chưa có distribution identity | Developer ID/notarization là blocker của Phase 6, không gọi ad-hoc bundle là production release |
| Trademark/kỳ vọng “WSL” | Dùng tên MSL; mô tả WSL-class experience, không tuyên bố binary/API compatibility với Microsoft WSL |

## Non-goals v1

- Hỗ trợ Intel Mac.
- Boot kernel hoặc cả distro x86_64; Rosetta chỉ dịch Linux user-space executable trong guest ARM64.
- Thay thế Docker Desktop hoặc trở thành Kubernetes distribution.
- Binary/API compatibility với `wsl.exe`, VHDX, Windows registry hoặc DirectX ABI.
- Bridged/LAN networking mặc định.
- Tự viết Linux syscall translation layer kiểu WSL 1.
- Dùng private Apple API, bundle hoặc phân phối lại Rosetta artifact.
- Tự viết hypervisor, CPU emulator hoặc fork toàn bộ WSLg khi framework/protocol upstream đáp ứng contract.

## Câu hỏi còn mở

1. QEMU compatibility được hỗ trợ trong bao nhiêu release sau GA?
2. Image catalog sẽ nằm ở GHCR hay registry khác, và ai sở hữu signing key?
3. Có Developer ID và hạ tầng notarization/update feed chưa?
4. Apple Container có cam kết export/snapshot API nào trong release target không?
5. Linux-native workspace sẽ dùng remote editor nào làm golden path, hay chỉ cung cấp protocol-neutral SSH?
6. Idle timeout mặc định nên là bao lâu trên máy 8 GB và 16 GB?
7. Telemetry/crash reporting có được chấp nhận không; nếu có phải opt-in và self-hosted hay third-party?
8. RDP RAIL/FreeRDP trên macOS có đáp ứng đủ per-window, clipboard, HiDPI và input không, hay phải dùng AppKit/Metal bridge?
9. Có đường GPU acceleration public, ổn định và license-compatible nào cho Linux guest trên các macOS mục tiêu không?
10. MSLg system distro sẽ được build/ký/phân phối thế nào để bảo toàn source provenance và license của Weston/XWayland/PipeWire?
11. Ma trận hỗ trợ Rosetta giữa macOS 26, macOS 27 và các release tiếp theo cần policy cài đặt/availability khác nhau ra sao?
12. USB/device attach nào thật sự cần cho developer workflow và có thể đáp ứng mà không thêm privileged helper quá rộng?

Các câu 2–3 chặn public beta; câu 4 chặn stable export/import; câu 8 và 10 chặn MSLg beta; câu 9 chặn GPU acceleration nhưng không chặn software-rendered MSLg; câu 11 chặn Rosetta GA. Các câu còn lại không chặn Phase 0–2.

## Definition of Done cho v1

V1 hoàn thành khi một người dùng trên Apple Silicon + macOS 26 có thể:

1. Cài package signed/notarized.
2. Cài Ubuntu mặc định từ CLI hoặc GUI mà không cần QEMU/Homebrew.
3. Gọi `msl` để vào shell, với cold/warm latency đạt performance budget.
4. Dùng systemd, package manager, Git và service local ổn định.
5. Chọn shared hoặc Linux-native workspace với tradeoff được giải thích.
6. Expose một localhost port có kiểm soát.
7. Stop/restart/update MSL mà không mất distro.
8. Dùng doctor/support bundle để chẩn đoán lỗi mà không lộ secret.
9. Quản lý cùng distro từ CLI và GUI với state nhất quán.
10. Mở app Linux Wayland và X11 thành cửa sổ macOS riêng, có Dock/Command-Tab và lifecycle đúng.
11. Dùng clipboard, audio, keyboard/IME, pointer và HiDPI trong Linux GUI app; microphone chỉ bật sau macOS consent.
12. Chạy workload Linux x86_64 được chọn trong distro ARM64 bằng Rosetta, hoặc nhận actionable capability error nếu host không hỗ trợ.
13. Update/rollback MSLg system distro mà không sửa hoặc làm mất dữ liệu user distro.

Export/import không phải blocker v1 nếu Apple runtime chưa có consistency primitive phù hợp; feature phải được đánh dấu experimental hoặc hoãn thay vì ship không an toàn.

Core GA có thể phát hành trước MSLg GA và Rosetta GA, nhưng product chỉ được mô tả là “WSL + WSLg-class” khi các mục 10–13 đều vượt release gate trên Apple Silicon thật.

## Nguồn chính thức dùng cho kế hoạch

- [Apple Container README](https://github.com/apple/container/blob/main/README.md)
- [Apple Container Machine guide](https://github.com/apple/container/blob/main/docs/container-machine.md)
- [Apple Container command reference](https://github.com/apple/container/blob/main/docs/command-reference.md)
- [Apple Container multiplatform images](https://github.com/apple/container/blob/main/docs/multiplatform-images.md)
- [Apple Containerization design](https://github.com/apple/containerization/blob/main/README.md)
- [Apple Virtualization framework](https://developer.apple.com/documentation/virtualization)
- [Apple: VZLinuxRosettaDirectoryShare](https://developer.apple.com/documentation/virtualization/vzlinuxrosettadirectoryshare)
- [Apple: Running Intel binaries in Linux VMs](https://developer.apple.com/documentation/virtualization/running-intel-binaries-in-linux-vms)
- [Apple: Running GUI Linux in a virtual machine on a Mac](https://developer.apple.com/documentation/virtualization/running-gui-linux-in-a-virtual-machine-on-a-mac)
- [Microsoft: Comparing WSL versions](https://learn.microsoft.com/en-us/windows/wsl/compare-versions)
- [Microsoft: Basic commands for WSL](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)
- [Microsoft: systemd in WSL](https://learn.microsoft.com/en-us/windows/wsl/systemd)
- [Microsoft: Import a custom Linux distribution](https://learn.microsoft.com/en-us/windows/wsl/use-custom-distro)
- [Microsoft WSLg architecture](https://github.com/microsoft/wslg)
- [Microsoft: Run Linux GUI apps with WSL](https://learn.microsoft.com/en-us/windows/wsl/tutorials/gui-apps)
- [Apple Container issue: amd64 Container Machine fails with exec format error](https://github.com/apple/container/issues/1843)
