# MobilVM — Android'de 16 / 32 / 64-bit x86 sanal makine

Telefonda ISO, IMG, QCOW2, VDI, VMDK, VHD ve disket imajı çalıştıran QEMU tabanlı sanal makine uygulamasının altyapısı.

| Mod | QEMU | Örnek sistemler |
|---|---|---|
| 16-bit | `qemu-system-i386 -cpu 486` | MS-DOS, FreeDOS, Windows 3.x |
| 32-bit | `qemu-system-i386 -cpu pentium3` | Windows 95/98/XP, 32-bit Linux |
| 64-bit | `qemu-system-x86_64 -cpu max` | Modern Linux, Windows 7/10 |

## Nasıl çalışır

```
MainActivity ──► VmEditActivity (ayarlar, ISO/disk seçme, qemu-img ile disk oluşturma)
     │
     ▼
VmService (ön plan servisi) ──► QEMU süreci  ──► 127.0.0.1:5901 VNC
                                                    │
DisplayActivity ◄── VncView ◄── RfbClient ◄─────────┘
 (dokunma → fare, klavye → keysym, alt tuş çubuğu)
```

- **QEMU ikilileri** `jniLibs/arm64-v8a/lib*.so` olarak APK'ya girer. Android 10+ uygulama klasöründen `exec()` izni vermez; ama `nativeLibraryDir` içinden verir. Bu yüzden `useLegacyPackaging = true` şart.
- **Bağımlı kütüphaneler + BIOS** `assets/qemu-runtime.zip` içindedir, ilk açılışta açılır (`QemuEnv.kt`).
- **Görüntü**: QEMU yerel VNC sunucusu açar; uygulama içindeki sıfır bağımlılıklı RFB istemcisi (`RfbClient.kt`) bağlanır.
- **Dosyalar**: Seçilen ISO/disk `Android/data/com.mobilvm.app/files/images/` altına kopyalanır (QEMU `content://` adreslerini açamaz).

## Dosyalar

```
app/src/main/java/com/mobilvm/app/
  MainActivity.kt     VM listesi
  VmEditActivity.kt   VM oluştur/düzenle, dosya içe aktar, yeni qcow2 disk
  VmConfig.kt         VM ayarları + JSON kayıt
  QemuEnv.kt          İkili yolları, runtime açma, ortam değişkenleri
  QemuCommand.kt      VmConfig → QEMU komut satırı
  VmService.kt        QEMU sürecini çalıştıran ön plan servisi + günlük
  DisplayActivity.kt  Ekran + tuş çubuğu (Esc, Ctrl, Alt, Ctrl+Alt+Del, F1-F12…)
  VncView.kt          Çizim, dokunma ve klavye
  RfbClient.kt        Minimal VNC istemcisi
  KeyMap.kt           Android tuşları → X11 keysym
scripts/fetch_qemu_termux.py   QEMU'yu Termux deposundan indirip yerleştirir
.github/workflows/build.yml    GitHub'da otomatik APK derleme
```

## Derleme

### A) Bilgisayar yoksa — GitHub Actions (telefondan yapılabilir)
1. GitHub'da yeni bir depo aç, bu klasördeki her şeyi yükle (`.github` klasörü dahil).
2. **Actions** sekmesi → "APK derle" kendiliğinden başlar (ya da *Run workflow*).
3. Bitince alttaki **Artifacts** kısmından `MobilVM-debug-apk` indir, zip'i aç, APK'yı kur.

### B) Android Studio
```bash
python3 scripts/fetch_qemu_termux.py     # jniLibs + assets/qemu-runtime.zip oluşur
```
Sonra projeyi Android Studio ile aç → Run.

## Kullanım
1. **+ Yeni sanal makine** → sistem türünü seç (16/32/64-bit).
2. **ISO seç** ve/veya **Yeni disk** ile boş bir qcow2 oluştur.
3. Kaydet → listeden VM'e dokun → **Başlat**.
4. Ekranda: dokun = sol tık, uzun bas / iki parmak = sağ tık, iki parmak kaydır = tekerlek. ⌨ tuşu klavyeyi açar.

## Bilmen gerekenler
- **Hız**: Telefonda KVM yok; her x86 komutu yazılımla çevriliyor. DOS, Win 9x, XP ve hafif Linux (Alpine, Debian netinst, antiX) rahat çalışır. Windows 10/11 açılır ama çok yavaştır.
- **Ses yok**: VNC ses taşımaz. Eklemek için `-audiodev` + AAudio/OpenSL köprüsü gerekir.
- **Aynı anda tek VM** (VNC portu sabit: 5901).
- **Klavye**: Türkçe karakterler için VM ayarında klavye düzenini `tr` yap.
- **Termux paketleri**: Script Termux'un aarch64 deposunu kullanır. Paket adı değişirse `BINARIES` listesini güncelle. `qemu-system-i386` bulunamazsa uygulama 16/32-bit için otomatik olarak x86_64 ikilisini kullanır.
- **Lisans**: QEMU GPLv2. APK'yı dağıtacaksan kaynak kodunu da yayınlamalısın.

## Sonraki adımlar (öneri)
- [ ] VNC'de **ZRLE/Tight** kodlaması (daha az CPU)
- [ ] **QEMU Extended Key Event** (-258): klavye düzeni sorunlarını kökten çözer
- [ ] **QMP** ile ACPI kapatma, anlık görüntü (snapshot), CD değiştirme
- [ ] Ses desteği
- [ ] Hazır şablonlar (FreeDOS, Win98, XP, Alpine…)
- [ ] Ayrıca ARM misafir desteği (`qemu-system-aarch64`, KVM'siz ama daha hızlı)
