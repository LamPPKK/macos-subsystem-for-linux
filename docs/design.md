# Thiết kế msl-arm

## Mục tiêu

Mục tiêu của MVP là biến proof-of-concept chạy Linux trong Terminal trên macOS thành một công cụ lặp lại được trên Apple Silicon:

- không cần cài Debian bằng tay;
- guest và host đều là ARM64 để HVF chạy gần native;
- state của mỗi VM tách biệt;
- không yêu cầu quyền `sudo`;
- mặc định chỉ mở SSH trên loopback;
- image tải về phải được kiểm checksum.

## Boot stack

```text
Apple Silicon
  -> macOS Hypervisor Framework (HVF)
    -> QEMU qemu-system-aarch64
      -> virt machine + host CPU
        -> EDK2 AArch64 UEFI
          -> Debian 13 ARM64 qcow2
            -> cloud-init NoCloud seed (CIDATA)
```

QEMU ghi rõ `qemu-system-aarch64` là binary dành cho guest AArch64. Machine `virt` là board tổng quát được khuyến nghị cho Linux, hỗ trợ virtio và CPU model `host` khi dùng HVF.

## Vì sao dùng cloud image

Repo proof-of-concept gốc cần tạo qcow2, boot netinst ISO, cài Debian, sửa GRUB và bật serial console thủ công. `msl-arm` dùng Debian cloud image chính thức để thay phần đó bằng một lệnh `init`.

Cloud-init seed là ISO9660/Joliet có volume label `CIDATA`, tạo bằng `hdiutil` có sẵn trên macOS. Seed chứa:

- hostname và instance ID;
- Linux user không có password;
- SSH public key;
- cấu hình `ttyAMA0` cho serial console;
- growpart/resize filesystem.

## Storage

Base image được tải một lần vào cache. Khi tạo VM, image được copy thành `disk.qcow2`, rồi `qemu-img resize` tăng virtual size. Việc copy tốn thêm vài trăm MB nhưng tránh backing-file dependency: di chuyển/xóa cache không làm VM hỏng.

UEFI code dùng file read-only đi kèm Homebrew QEMU. UEFI variable template được copy riêng cho từng VM, đúng mô hình firmware descriptor chính thức của QEMU.

## Network và access

QEMU user-mode networking không cần `sudo`. Chỉ có một host forward:

```text
tcp:127.0.0.1:<configured port> -> guest:22
```

Root login và password SSH đều bị khóa. Public key được inject qua cloud-init; private key luôn ở host.

## Lifecycle

- Foreground: serial console đi thẳng vào Terminal qua `-nographic`.
- Background: QEMU daemonize và mở Unix serial socket.
- Stop: CLI gửi `system_powerdown` vào QEMU monitor socket, thay vì kill cứng nếu monitor còn hoạt động.
- PID, serial socket và monitor socket đều nằm trong thư mục của VM.
