#!/usr/bin/env bash
# CI'da işletim sistemi algılama testleri için gerçek imajlar üretir / indirir.
set -euo pipefail
OUT="${1:?çıktı klasörü}"
mkdir -p "$OUT"
WORK="$(mktemp -d)"
sudo apt-get install -y -qq nasm xorriso grub-pc-bin grub-common mtools fonts-roboto fonts-noto-core >/dev/null

# Arayüz testleri için gerçek fontlar (Roboto ağırlıkları + Arapça)
FONTS="${STRATA_TEST_FONTS:-$OUT/fonts}"
mkdir -p "$FONTS"
for f in Roboto-Regular Roboto-Medium Roboto-Bold Roboto-Black NotoSansArabic-Regular NotoSansArabic-Bold; do
  src="$(find /usr/share/fonts -name "$f.ttf" | head -1)"
  if [ -n "$src" ]; then cp "$src" "$FONTS/"; fi
done
ls "$FONTS"

# --- 1) Kendi yapımı OS: GRUB + Multiboot2, 32-bit ve 64-bit (uzun moda geçen) çekirdek
make_kernel() { # $1=ad $2=ekstra komut
  cat > "$WORK/$1.asm" <<ASM
bits 32
section .text
align 8
header:
  dd 0xE85250D6
  dd 0
  dd header_end - header
  dd -(0xE85250D6 + 0 + (header_end - header))
  dw 0, 0
  dd 8
header_end:
global _start
_start:
  cli
  $2
.halt:
  hlt
  jmp .halt
ASM
  nasm -f elf32 "$WORK/$1.asm" -o "$WORK/$1.o"
  mkdir -p "$WORK/$1/boot/grub"
  ld -m elf_i386 -e _start -Ttext 0x100000 -o "$WORK/$1/boot/kernel.bin" "$WORK/$1.o"
  printf 'set timeout=0\nmenuentry "myos" {\n  multiboot2 /boot/kernel.bin\n  boot\n}\n' > "$WORK/$1/boot/grub/grub.cfg"
  grub-mkrescue -o "$OUT/$1.iso" "$WORK/$1" 2>/dev/null
}
make_kernel myos32 "nop"
make_kernel myos64 "mov ecx, 0xC0000080
  rdmsr
  or eax, 0x100
  wrmsr"

# --- 2) Ham önyükleme disketleri (kendi önyükleyicisi olan sistemler)
cat > "$WORK/boot16.asm" <<'ASM'
org 0x7c00
bits 16
  mov ah, 0x0e
  mov al, 'A'
  int 0x10
  jmp $
times 510-($-$$) db 0
dw 0xAA55
ASM
cat > "$WORK/boot32.asm" <<'ASM'
org 0x7c00
bits 16
  cli
  lgdt [gdtr]
  mov eax, cr0
  or al, 1
  mov cr0, eax
  jmp 0x08:pm
bits 32
pm:
  hlt
gdt: dq 0, 0x00CF9A000000FFFF, 0x00CF92000000FFFF
gdtr: dw 23
      dd gdt
times 510-($-$$) db 0
dw 0xAA55
ASM
for n in boot16 boot32; do
  nasm -f bin "$WORK/$n.asm" -o "$OUT/$n.img"
  truncate -s 1474560 "$OUT/$n.img"
done

# --- 3) live-build (Debian) yapısında özel dağıtım: TyrOS benzeri
LB="$WORK/livebuild"
mkdir -p "$LB/.disk" "$LB/live" "$LB/isolinux" "$LB/boot/grub"
echo 'Debian GNU/Linux trixie "Trixie" - Official Snapshot amd64 LIVE Binary 20251121-12:00' > "$LB/.disk/info"
python3 - "$LB/live/vmlinuz" <<'PY'
import sys
b = bytearray(16384)
b[0x1FE:0x200] = b'\x55\xAA'
b[0x202:0x206] = b'HdrS'          # Linux bzImage başlığı
b[0x236] = 0x01                   # XLF_KERNEL_64
open(sys.argv[1], 'wb').write(b)
PY
head -c 4096 /dev/urandom > "$LB/live/initrd.img"
truncate -s 900M "$LB/live/filesystem.squashfs"
printf 'label live\n  kernel /live/vmlinuz\n  append initrd=/live/initrd.img boot=live components quiet splash\n' > "$LB/isolinux/isolinux.cfg"
printf 'menuentry "Start TyrOS" {\n  linux /live/vmlinuz boot=live\n  initrd /live/initrd.img\n}\n' > "$LB/boot/grub/grub.cfg"
xorriso -as mkisofs -quiet -R -J -V "TyrOS 1.0" -o "$OUT/TyrOS_v1_0 (3).iso" "$LB"
# .disk olmadan, sadece live klasörüyle
rm -rf "$LB/.disk"
xorriso -as mkisofs -quiet -R -J -V "MYDISTRO" -o "$OUT/livebuild-nodisk.iso" "$LB"

# --- 4) Gerçek Linux ISO'ları (adı anlamsız yapılarak: içerikten tanınmalı)
curl -fsSL -o "$OUT/mystery-a.iso" https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/alpine-virt-3.20.3-x86_64.iso || true
curl -fsSL -o "$OUT/mystery-b.iso" http://tinycorelinux.net/15.x/x86/release/Core-current.iso || true
ls -la "$OUT"
