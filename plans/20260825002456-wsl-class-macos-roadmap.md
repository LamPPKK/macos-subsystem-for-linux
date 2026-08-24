# Kế hoạch MSL: Linux subsystem cấp độ WSL cho macOS

- Trạng thái: Proposed
- Ngày: 2026-08-25
- Đối tượng: maintainer, contributor và người kiểm thử MSL
- Phạm vi mục tiêu: Mac Apple Silicon, terminal-first, Apple Container Machine là runtime ưu tiên

## Tóm tắt quyết định

MSL sẽ trở thành một Linux subsystem được quản lý, không phải một ứng dụng VM truyền thống. Người dùng cài một lần, gọi `msl` từ Terminal để vào distro mặc định, và chỉ mở MSL Settings khi muốn tạo distro, chỉnh tài nguyên hoặc chẩn đoán lỗi.

Kiến trúc được khuyến nghị:

1. Dùng Apple Container Machine làm runtime chính trên Apple Silicon và macOS 26 trở lên.
2. Thêm một daemon theo user là `msld` làm control plane duy nhất cho CLI và GUI.
3. Xây CLI `msl` với mental model gần WSL: install, list, run, exec, stop, shutdown, set-default, config, export, import và doctor.
4. Giữ QEMU/HVF làm compatibility backend trong giai đoạn chuyển tiếp; không đầu tư thêm một VMM riêng trước khi có gap đã được benchmark và chứng minh.
5. Tối ưu cho Terminal và developer workflow; Linux GUI/WSLg không thuộc v1.

Quyết định này ưu tiên độ mượt, độ an toàn dữ liệu và chi phí bảo trì thấp hơn việc hỗ trợ mọi phiên bản macOS ngay từ đầu.

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

### Điều Apple đã cung cấp

Apple Container chạy OCI image trong lightweight Linux VM, tối ưu cho Apple silicon. Container Machine bổ sung đúng các primitive gần WSL: machine persistent, init system, user khớp host, home sharing, boot-on-run, nhiều distro, CPU/RAM config và lifecycle command. Containerization phía dưới đã có Virtualization.framework, ext4, optimized kernel, networking và guest control qua vsock.

Vì vậy, viết lại Virtualization.framework backend ngay sẽ trùng phần khó nhất mà Apple đã triển khai. MSL nên đặt stable product contract phía trên Apple Container và chỉ mở capability cho backend khác khi cần.

## Product promise

V1 phải tạo được trải nghiệm sau:

- Sau khi hoàn tất installer, người dùng mở Terminal và gọi `msl` để vào Ubuntu mặc định.
- Nếu distro đang tắt, MSL tự boot và đưa ra prompt mà không lộ bước quản trị VM.
- CLI và MSL Settings luôn thấy cùng state, cùng lỗi và cùng tiến trình operation.
- Distro giữ nguyên package, service và file qua restart.
- Project có thể chạy theo hai mode: shared workspace để tiện chỉnh sửa bằng app macOS, hoặc Linux-native workspace để tối đa I/O.
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

Không được tối ưu bằng cách giữ tất cả distro chạy vĩnh viễn. Chính sách warm/idle phải có giới hạn rõ ràng và người dùng có thể tắt.

## Kiến trúc đích

### Frontend

- `msl`: CLI chính, ưu tiên startup nhanh và output ổn định cho người lẫn automation.
- MSL Settings: GUI native để install distro, cấu hình CPU/RAM/home, xem health/log, đặt default và quản lý storage.
- Terminal: data plane tương tác duy nhất trong v1; app chỉ yêu cầu daemon mở phiên shell.

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

- Apple Container Machine: backend production mặc định.
- QEMU/HVF: read/launch compatibility cho VM hiện có; deprecate dần sau khi có migration an toàn.
- Virtualization.framework backend riêng: chỉ bắt đầu nếu benchmark hoặc product requirement chứng minh Apple Container không thể đáp ứng một capability bắt buộc. Đây không phải dependency của v1.

Mọi call đến CLI ngoài phải dùng argument array, tách stdout/stderr, timeout, cancellation và version probe. Không parse table nếu JSON/machine-readable format có sẵn.

### Guest contract

Default image là Ubuntu LTS có systemd và một gói guest integration nhỏ, versioned độc lập với app.

Guest integration phụ trách:

- readiness signal sau boot;
- chuẩn hóa user/default shell và environment;
- path/workspace metadata;
- service/port discovery tùy chọn;
- shutdown acknowledgement;
- version/capability report.

Không dựa vào API vsock chưa được Apple công bố cho third party. Phase đầu dùng các entrypoint được Apple Container hỗ trợ công khai; transport khác chỉ được thêm sau capability spike.

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
- Ghi baseline trên ít nhất M1 8 GB, M2 16 GB và M3; dùng macOS 26 release hiện hành.

Exit gate: benchmark reproducible, lifecycle invariants được review, không còn câu hỏi chặn thiết kế daemon.

### Phase 1 — Shared core, CLI `msl` và daemon `msld`

Mục tiêu: một control plane cho mọi frontend.

- Tách domain/runtime code khỏi SwiftUI thành package dùng chung.
- Thêm LaunchAgent, versioned XPC, operation queue, event stream và recovery journal.
- Thêm CLI read path và interactive session path.
- Chuyển GUI từ direct `Process` sang XPC.

Exit gate: CLI và GUI luôn đồng bộ state; daemon restart giữa create/stop không làm hỏng distro; list đạt SLO.

### Phase 2 — Golden Ubuntu và lifecycle production

Mục tiêu: install-to-shell một bước.

- Xuất bản Ubuntu LTS machine image được pin digest, systemd-ready và có guest integration.
- Thực hiện install, boot-on-run, exec, stop, default distro, config và logs qua Apple backend.
- Thêm image progress, retry/resume, version probe và actionable doctor.
- Bảo toàn QEMU VM hiện có ở compatibility view.

Exit gate: fresh machine đi từ installer đến shell không cần QEMU/Homebrew; cold/warm targets đạt trên baseline hoặc có accepted exception kèm số liệu.

### Phase 3 — Terminal, workspace và localhost integration

Mục tiêu: developer workflow hằng ngày không có “VM friction”.

- Hoàn thiện TTY, signal, cwd/path translation và Terminal launch.
- Ship shared và Linux-native workspace modes.
- Thêm explicit port exposure, stable hostname và collision handling.
- Tài liệu remote editor cho Linux-native workspace.

Exit gate: compatibility suite cho shell phổ biến, benchmark filesystem công bố, service trong guest truy cập được qua localhost mapping sau restart.

### Phase 4 — GUI production và release pipeline

Mục tiêu: MSL Settings đủ chất lượng phân phối.

- Onboarding, install/catalog, operation progress, storage view, diagnostics và destructive confirmations.
- Accessibility, keyboard navigation, localization foundation và crash reporting opt-in.
- Developer ID, notarization, signed update feed và rollback release.

Exit gate: app qua accessibility checklist, upgrade từ hai version trước giữ nguyên distro, Gatekeeper chấp nhận clean install.

### Phase 5 — Portability và ecosystem

Mục tiêu: import/export an toàn và nhiều distro.

- Hoàn tất export/import sau consistency spike.
- Thêm Debian và custom image validation profile.
- IDE hooks, dotfiles bootstrap và optional container engine inside distro.
- Đánh giá lại native Virtualization.framework backend dựa trên gap/benchmark thực tế.

Exit gate: restore test bit-for-bit ở scope đã cam kết, failure injection không làm mất source distro, custom image lỗi bị chặn trước create.

### Phase 6 — GA hardening

Mục tiêu: độ tin cậy đủ cho daily driver.

- Soak test nhiều ngày, memory/disk pressure, sleep/wake, network changes và abrupt reboot.
- Upgrade/downgrade matrix cho macOS, Apple Container, MSL và guest image.
- Security review, threat model, recovery runbook và support bundle redaction.

Exit gate: không còn P0/P1, data-integrity suite pass, performance budget pass và release rollback đã diễn tập.

## Thay đổi dự kiến theo khu vực repo

| Khu vực | Hướng thay đổi |
| --- | --- |
| `App/MSLSettings` | Giữ SwiftUI; thay direct runtime client bằng XPC client và shared models |
| `App/MSLSettings/Sources/MSLControlCore` | Tách thành core package độc lập UI, thêm state machine và capability model |
| `Daemon/MSLD` | LaunchAgent, XPC service, operation journal, runtime orchestration |
| `CLI/MSL` | CLI nhanh, TTY/session handling, JSON schema |
| `Guest` | guest integration package, readiness và compatibility contract |
| `images` | reproducible image build, pinned inputs, provenance và SBOM |
| `tests` | contract, integration, failure injection, performance và upgrade matrix |
| `scripts`/release | signing, notarization, update feed và artifact verification |
| `bin/msl-arm` | compatibility backend; đóng băng feature sau migration tooling |

Tên thư mục mới là đề xuất và có thể đổi trong Phase 0, nhưng boundary frontend/core/daemon/runtime/guest là invariant kiến trúc.

## Validation strategy

### Mỗi pull request

- Swift unit tests, strict concurrency, shell lint và schema compatibility.
- Fake runtime contract tests cho mọi error/timeout/cancel path.
- Data mutation tests phải chứng minh target path và atomicity.
- Benchmark smoke test với regression threshold rộng.

### CI Apple Silicon bắt buộc

- Self-hosted Mac Apple Silicon chạy macOS 26 và Apple Container release được pin.
- Install image, create, cold/warm exec, systemd service, stop/restart/delete.
- Shared workspace permissions, symlink, case sensitivity và large/small file workload.
- Network mapping, sleep/wake, service restart và daemon crash recovery.
- Signed app install, first launch, update và rollback.

### Release gate

- Test trên M1/M2/M3-or-newer và host RAM 8/16/32 GB.
- Ít nhất 100 lifecycle loops mỗi baseline, 24 giờ soak và abrupt reboot recovery.
- Export/import test nếu feature được bật.
- Không regression quá 10% ở p95 startup/exec so với release trước nếu không có waiver công khai.
- Support bundle đã kiểm redaction; không chứa token, private key hoặc nội dung file người dùng.

## Rủi ro và giảm thiểu

| Rủi ro | Giảm thiểu |
| --- | --- |
| Apple Container command/JSON thay đổi | Version probe, adapter theo release, contract fixtures và pin minimum/maximum đã test |
| macOS 26 giới hạn adoption | QEMU compatibility, nhưng product target vẫn ưu tiên macOS 26 để tránh kéo chậm core path |
| Shared home chậm với workload nhiều file | Hai workspace mode, benchmark công khai, Linux-native là recommendation cho workload nặng |
| First pull/build lâu | Prebuilt signed image, progress/resume, background prefetch sau consent |
| Runtime thiếu snapshot/export | Không giả lập vội; capability gate và guest-coordinated consistency spike |
| Daemon trở thành single point of failure | Journal, idempotent operations, reconcile runtime on launch và crash injection tests |
| Xóa nhầm persistent storage | Typed destructive API, exact-name confirmation, backup gate và không dùng broad path deletion |
| App chưa có distribution identity | Developer ID/notarization là blocker của Phase 4, không gọi ad-hoc bundle là production release |
| Trademark/kỳ vọng “WSL” | Dùng tên MSL; mô tả WSL-class experience, không tuyên bố binary/API compatibility với Microsoft WSL |

## Non-goals v1

- Chạy Linux GUI app kiểu WSLg.
- Hỗ trợ Intel Mac.
- Thay thế Docker Desktop hoặc trở thành Kubernetes distribution.
- Binary compatibility với `wsl.exe` hay format VHDX.
- Bridged/LAN networking mặc định.
- Tự viết Linux syscall translation layer kiểu WSL 1.
- Tự xây VMM riêng khi Apple Container vẫn đáp ứng product contract.

## Câu hỏi còn mở

1. QEMU compatibility được hỗ trợ trong bao nhiêu release sau GA?
2. Image catalog sẽ nằm ở GHCR hay registry khác, và ai sở hữu signing key?
3. Có Developer ID và hạ tầng notarization/update feed chưa?
4. Apple Container có cam kết export/snapshot API nào trong release target không?
5. Linux-native workspace sẽ dùng remote editor nào làm golden path, hay chỉ cung cấp protocol-neutral SSH?
6. Idle timeout mặc định nên là bao lâu trên máy 8 GB và 16 GB?
7. Telemetry/crash reporting có được chấp nhận không; nếu có phải opt-in và self-hosted hay third-party?

Các câu 2–3 chặn public beta; câu 4 chặn stable export/import; các câu còn lại không chặn Phase 0–2.

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

Export/import không phải blocker v1 nếu Apple runtime chưa có consistency primitive phù hợp; feature phải được đánh dấu experimental hoặc hoãn thay vì ship không an toàn.

## Nguồn chính thức dùng cho kế hoạch

- [Apple Container README](https://github.com/apple/container/blob/main/README.md)
- [Apple Container Machine guide](https://github.com/apple/container/blob/main/docs/container-machine.md)
- [Apple Container command reference](https://github.com/apple/container/blob/main/docs/command-reference.md)
- [Apple Containerization design](https://github.com/apple/containerization/blob/main/README.md)
- [Apple Virtualization framework](https://developer.apple.com/documentation/virtualization)
- [Microsoft: Comparing WSL versions](https://learn.microsoft.com/en-us/windows/wsl/compare-versions)
- [Microsoft: Basic commands for WSL](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)
- [Microsoft: systemd in WSL](https://learn.microsoft.com/en-us/windows/wsl/systemd)
- [Microsoft: Import a custom Linux distribution](https://learn.microsoft.com/en-us/windows/wsl/use-custom-distro)
