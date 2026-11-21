#!/usr/bin/env python3
"""
Termux (aarch64) paket deposundan hazır derlenmiş QEMU'yu indirir ve projeye yerleştirir.

  Çalıştırılabilirler          -> android/app/src/main/jniLibs/arm64-v8a/lib*.so
  Kütüphaneler + BIOS dosyaları -> android/app/src/main/assets/qemu-runtime.zip

Kullanım:
  python3 scripts/fetch_qemu_termux.py            # x86_64 + i386 + qemu-img
  python3 scripts/fetch_qemu_termux.py --no-i386  # sadece x86_64 (16/32-bit'i de çalıştırır)

Not: QEMU GPLv2 lisanslıdır. APK'yı dağıtırsan kaynak kodu da sunmalısın.
"""
import argparse
import json
import gzip
import io
import lzma
import os
import posixpath
import re
import shutil
import sys
import tarfile
import tempfile
import urllib.request
import zipfile

DEFAULT_MIRROR = "https://packages-cf.termux.dev/apt/termux-main"
PREFIX = "/data/data/com.termux/files/usr"

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JNI_DIR = os.path.join(ROOT_DIR, "android", "app", "src", "main", "jniLibs", "arm64-v8a")
ASSET_ZIP = os.path.join(ROOT_DIR, "android", "app", "src", "main", "assets", "qemu-runtime.zip")
ASSET_INFO = os.path.join(ROOT_DIR, "android", "app", "src", "main", "assets", "qemu-runtime.json")

# (aday paket adları, usr/bin içindeki ad, APK içindeki ad)
BINARIES = [
    (["qemu-system-x86-64-headless", "qemu-system-x86-64"], "qemu-system-x86_64", "libqemu-system-x86_64.so"),
    (["qemu-system-i386-headless", "qemu-system-i386"], "qemu-system-i386", "libqemu-system-i386.so"),
    (["qemu-utils"], "qemu-img", "libqemu-img.so"),
    # Diğer mimariler: aarch64 32-bit ARM'ı, ppc64 32-bit PowerPC Mac'leri de çalıştırır
    (["qemu-system-aarch64-headless", "qemu-system-aarch64"], "qemu-system-aarch64", "libqemu-system-aarch64.so"),
    (["qemu-system-ppc64-headless", "qemu-system-ppc64"], "qemu-system-ppc64", "libqemu-system-ppc64.so"),
    (["qemu-system-riscv64-headless", "qemu-system-riscv64"], "qemu-system-riscv64", "libqemu-system-riscv64.so"),
    # 68k: Macintosh Quadra 800 ve m68k Linux. (SPARC, MIPS, s390x, PA-RISC, Alpha, LoongArch
    # motorlarını Termux yayınlamıyor; onlar için QEMU'yu kendimiz derlememiz gerekir.)
    (["qemu-system-m68k-headless", "qemu-system-m68k"], "qemu-system-m68k", "libqemu-system-m68k.so"),
]

# Çalışma zamanında gereksiz olan bağımlılıklar
SKIP = {"termux-tools", "termux-exec", "termux-am", "termux-keyring", "dash", "bash",
        "coreutils", "dpkg", "apt", "findutils", "grep", "sed", "less", "procps"}

SO_RE = re.compile(r"^lib.*\.so(\.\d+)*$")


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "mobilvm-fetch/1.0"})
    with urllib.request.urlopen(req, timeout=300) as r:
        return r.read()


# ----------------------------------------------------------------- paket listesi

def parse_packages(text, pkgs):
    for stanza in text.split("\n\n"):
        fields, key = {}, None
        for line in stanza.splitlines():
            if line[:1] in (" ", "\t") and key:
                fields[key] += "\n" + line.strip()
            elif ":" in line:
                key, _, val = line.partition(":")
                key = key.strip()
                fields[key] = val.strip()
        if "Package" in fields and "Filename" in fields:
            pkgs.setdefault(fields["Package"], fields)
            for prov in fields.get("Provides", "").split(","):
                prov = re.sub(r"\(.*?\)", "", prov).strip()
                if prov:
                    pkgs.setdefault(prov, fields)


def load_index(mirror):
    pkgs = {}
    for arch in ("aarch64", "all"):
        url = f"{mirror}/dists/stable/main/binary-{arch}/Packages"
        try:
            parse_packages(fetch(url).decode("utf-8", "replace"), pkgs)
            print(f"✓ {url}")
        except Exception as e:  # noqa: BLE001
            print(f"! {url}: {e}")
    if not pkgs:
        sys.exit("Paket listesi indirilemedi.")
    return pkgs


def deps_of(fields):
    out = []
    for key in ("Pre-Depends", "Depends"):
        for part in fields.get(key, "").split(","):
            alts = [re.sub(r"\(.*?\)", "", a).strip().split(":")[0] for a in part.split("|")]
            alts = [a for a in alts if a]
            if alts:
                out.append(alts)
    return out


def resolve(pkgs, roots):
    seen, order, stack = set(), [], list(roots)
    while stack:
        name = stack.pop()
        if name in seen or name in SKIP:
            continue
        seen.add(name)
        f = pkgs.get(name)
        if f is None:
            print(f"! bulunamadı, atlanıyor: {name}")
            continue
        real = f["Package"]
        if real != name and real in seen:
            continue
        seen.add(real)
        order.append(real)
        for alts in deps_of(f):
            stack.append(next((a for a in alts if a in pkgs), alts[0]))
    return order


# ----------------------------------------------------------------- .deb açma

def ar_members(data):
    if not data.startswith(b"!<arch>\n"):
        raise ValueError("geçerli bir .deb (ar) değil")
    pos = 8
    while pos + 60 <= len(data):
        hdr = data[pos:pos + 60]
        name = hdr[:16].decode("ascii", "replace").strip().rstrip("/")
        size = int(hdr[48:58].decode("ascii").strip())
        yield name, data[pos + 60:pos + 60 + size]
        pos += 60 + size + (size & 1)


def decompress(name, blob):
    if name.endswith(".xz"):
        return lzma.decompress(blob)
    if name.endswith(".gz"):
        return gzip.decompress(blob)
    if name.endswith(".zst"):
        try:
            import zstandard  # type: ignore
        except ImportError:
            sys.exit("data.tar.zst için: pip install zstandard")
        return zstandard.ZstdDecompressor().decompressobj().decompress(blob)
    if name.endswith(".tar"):
        return blob
    raise ValueError(f"bilinmeyen sıkıştırma: {name}")


def norm_member(name):
    while name.startswith("./"):
        name = name[2:]
    name = posixpath.normpath("/" + name.lstrip("/"))
    return None if name in ("/", "/.") else name


def extract_deb(deb, staging, links):
    """Sadece normal dosya ve klasörleri diske yazar; bağlantılar `links` sözlüğüne kaydedilir
    (diske symlink yazılmaz, böylece arşiv dışına yazma olmaz)."""
    data = next(((n, b) for n, b in ar_members(deb) if n.startswith("data.tar")), None)
    if data is None:
        raise ValueError("data.tar bulunamadı")
    raw = decompress(*data)
    with tarfile.open(fileobj=io.BytesIO(raw)) as tf:
        for m in tf.getmembers():
            p = norm_member(m.name)
            if p is None:
                continue
            target = os.path.join(staging, p.lstrip("/"))
            if m.isdir():
                os.makedirs(target, exist_ok=True)
            elif m.issym():
                links[p] = m.linkname
            elif m.islnk():
                lp = norm_member(m.linkname)
                if lp:
                    links[p] = lp
            elif m.isfile():
                os.makedirs(os.path.dirname(target), exist_ok=True)
                if os.path.islink(target):
                    os.unlink(target)
                with tf.extractfile(m) as src, open(target, "wb") as dst:
                    shutil.copyfileobj(src, dst)
                os.chmod(target, 0o755 if m.mode & 0o111 else 0o644)


def real_file(staging, links, p):
    for _ in range(40):
        if p in links:
            t = links[p]
            p = posixpath.normpath(t if t.startswith("/") else posixpath.join(posixpath.dirname(p), t))
            continue
        fs = os.path.join(staging, p.lstrip("/"))
        return fs if os.path.isfile(fs) else None
    return None


def list_dir(staging, links, d):
    names = set()
    fs = os.path.join(staging, d.lstrip("/"))
    if os.path.isdir(fs):
        names |= {n for n in os.listdir(fs) if os.path.isfile(os.path.join(fs, n))}
    names |= {posixpath.basename(k) for k in links if posixpath.dirname(k) == d}
    return names


def walk_tree(staging, links, d):
    """d altındaki tüm dosyaların göreli yollarını döndürür."""
    out = set()
    fs = os.path.join(staging, d.lstrip("/"))
    if os.path.isdir(fs):
        for root, _, files in os.walk(fs):
            for f in files:
                out.add(os.path.relpath(os.path.join(root, f), fs).replace(os.sep, "/"))
    for k in links:
        if k.startswith(d + "/"):
            out.add(k[len(d) + 1:])
    return out


# ----------------------------------------------------------------- toplama

def collect(staging, links):
    os.makedirs(JNI_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(ASSET_ZIP), exist_ok=True)

    found = 0
    for _, src, dst in BINARIES:
        f = real_file(staging, links, f"{PREFIX}/bin/{src}")
        if f:
            shutil.copyfile(f, os.path.join(JNI_DIR, dst))
            print(f"✓ {src} -> jniLibs/arm64-v8a/{dst} ({os.path.getsize(f) // 1024} KB)")
            found += 1
        else:
            print(f"! {src} bulunamadı")
    if found == 0:
        sys.exit("Hiç QEMU ikilisi bulunamadı.")

    count = 0
    with zipfile.ZipFile(ASSET_ZIP, "w", zipfile.ZIP_DEFLATED) as z:
        for name in sorted(list_dir(staging, links, f"{PREFIX}/lib")):
            if not SO_RE.match(name):
                continue
            f = real_file(staging, links, f"{PREFIX}/lib/{name}")
            if f:
                z.write(f, f"lib/{name}"); count += 1
        for rel in sorted(walk_tree(staging, links, f"{PREFIX}/lib/qemu")):
            if rel.endswith(".so"):
                f = real_file(staging, links, f"{PREFIX}/lib/qemu/{rel}")
                if f:
                    z.write(f, f"lib/qemu/{rel}"); count += 1
        for rel in sorted(walk_tree(staging, links, f"{PREFIX}/share/qemu")):
            f = real_file(staging, links, f"{PREFIX}/share/qemu/{rel}")
            if f:
                z.write(f, f"share/qemu/{rel}"); count += 1
    with zipfile.ZipFile(ASSET_ZIP) as z:
        total = sum(i.file_size for i in z.infolist())
        names = set(z.namelist())
    # Uygulamanın kullandığı donanımlar için gereken firmware / klavye dosyaları
    required = ["bios-256k.bin", "vgabios-cirrus.bin", "vgabios-stdvga.bin", "vgabios-vmware.bin",
                "vgabios-virtio.bin", "kvmvapic.bin", "linuxboot_dma.bin", "multiboot_dma.bin",
                "edk2-x86_64-code.fd", "edk2-i386-code.fd", "edk2-i386-vars.fd",
                # ARM, PowerPC, RISC-V
                "edk2-aarch64-code.fd", "edk2-arm-code.fd", "edk2-arm-vars.fd",
                "openbios-ppc", "qemu_vga.ndrv", "slof.bin",
                "opensbi-riscv64-generic-fw_dynamic.bin", "edk2-riscv-code.fd", "edk2-riscv-vars.fd"]
    keymaps = ["en-us", "tr", "en-gb", "de", "fr", "es", "it", "pt-br", "ru", "ja"]
    missing = [r for r in required if f"share/qemu/{r}" not in names]
    missing += [f"keymaps/{k}" for k in keymaps if f"share/qemu/keymaps/{k}" not in names]
    print("share/qemu:", " ".join(sorted(n[len("share/qemu/"):] for n in names
                                         if n.startswith("share/qemu/") and "/keymaps/" not in n)))
    print("EKSIK:" if missing else "✓ Gerekli tüm firmware ve klavye dosyaları mevcut", " ".join(missing))
    # Motorlarda derlenmiş özellikler (ses kartları, pano, vvfat, dmg...)
    probes = ["AC97", "sb16", "intel-hda", "hda-duplex", "hda-output", "virtio-sound", "virtio-snd", "es1370",
              "adlib", "gus", "cs4231a", "pcspk", "qemu-vdagent", "virtserialport", "vvfat", "dmg", "screamer",
              "usb-audio", "audiodev", "virtio-gpu", "virtio-keyboard", "ati-vga", "bochs-display", "qxl"]
    for f in sorted(os.listdir(JNI_DIR)):
        if not f.startswith("libqemu-system"):
            continue
        data = open(os.path.join(JNI_DIR, f), "rb").read()
        have = [p for p in probes if p.encode() in data]
        print(f"ÖZELLİK {f}: {' '.join(have)}")
    print("FIRMWARE:", " ".join(sorted(n[len("share/qemu/"):] for n in names
                                       if n.startswith("share/qemu/") and "/keymaps/" not in n)))
    with open(ASSET_INFO, "w") as f:
        json.dump({"files": count, "bytes": total}, f)
    print(f"✓ {count} dosya -> assets/qemu-runtime.zip ({os.path.getsize(ASSET_ZIP) // (1 << 20)} MB)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mirror", default=DEFAULT_MIRROR)
    ap.add_argument("--no-i386", action="store_true", help="qemu-system-i386'yı atla")
    args = ap.parse_args()
    mirror = args.mirror.rstrip("/")

    pkgs = load_index(mirror)
    roots = []
    for cands, src, _ in BINARIES:
        if args.no_i386 and "i386" in src:
            continue
        pick = next((c for c in cands if c in pkgs), None)
        if pick:
            roots.append(pick)
        else:
            print(f"! {src} için paket yok: {cands}")

    order = resolve(pkgs, roots)
    print(f"{len(order)} paket indirilecek: {', '.join(order)}")
    with tempfile.TemporaryDirectory() as tmp:
        staging = os.path.join(tmp, "root")
        links = {}
        for name in order:
            f = pkgs[name]
            print(f"↓ {name} {f.get('Version', '')}")
            extract_deb(fetch(f"{mirror}/{f['Filename']}"), staging, links)
        collect(staging, links)
    print("Bitti. Şimdi APK'yı derleyebilirsin.")


if __name__ == "__main__":
    main()
