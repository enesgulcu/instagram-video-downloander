# FFmpeg Otomasyon Sistemi - Kullanim Rehberi

Bu proje, Instagram linklerinden videolari indirip ikili gruplar halinde tek ciktiya donusturur.

Temel hedef:
- `input` klasorundeki videolari ikiserli eslestirmek
- her cift icin tek bir cikti uretmek
- ornek akış: `1.son5sn + 1.tamami + 2.son5sn + 2.tamami`

> 20 input video varsa hedef 10 output videodur. Tek sayi olursa son video ilk video ile eslestirilir.

## 1) Proje dosyalari

- `RUN.bat`: tum sureci baslatir (onerilen giris noktasi).
- `RESET.bat`: tum calisma verisini sifirlar (temiz baslangic).
- `start-run.ps1`: baslatma katmani; setup sorusu + pipeline cagrisi.
- `run-pipeline.ps1`: indirme + isleme + ozet raporu.
- `download-instagram.ps1`: indirme, tekrar deneme, duplicate/arsiv kontrolu.
- `process-videos.ps1`: ikili birlestirme ve ffmpeg isleme adimlari.
- `setup.ps1`: ffmpeg / yt-dlp kurulum kontrolu.

## 2) Hizli kullanim (onerilen)

1. `instagram-links.txt` dosyasina linkleri yaz.
2. `RUN.bat` calistir.
3. Kurulum sorusuna:
   - yeni cihazsa `E`
   - kurulum zaten varsa `Enter`
4. Islem bitince ciktilari `output` klasorunde kontrol et.

## 3) Isleyis mantigi

1. Linklerden videolar `input` klasorune indirilir.
2. Daha once indirilen icerikler arsivden kontrol edilir ve tekrar indirilmez.
3. Video ciftleri olusturulur (`1-2`, `3-4`, `5-6`, ...).
4. Her cift icin tek output uretilir.

Notlar:
- Isleme stabilite icin su an sirali (tek worker) ilerler.
- Sorunlu bir cift olursa loglanir ve diger ciftlerle devam edilir.

## 4) Duplicate (tekrar) engelleme

Tekrar indirmeyi engelleyen mekanizmalar:
- `input\downloaded-archive.txt` (arsiv ID kaydi)
- `input` klasorundeki mevcut videolardan arsive senkron

Bu sayede ayni icerik icin su tip mesajlar gorulur:
- `Atlandi ... Daha once bu icerik indirildi/paylasildi, tekrar indirilmedi.`

## 5) Raporlar ve loglar

- `download-report.csv`: indirmenin sonucu (`downloaded_or_skipped`, `already_downloaded`, `error`)
- `process-report.csv`: isleme sonucu (cift bazli basari/hata)
- `run-summary.json`: son kosunun ozet metrikleri
- `pipeline-master-log.jsonl`: her kosunun satir bazli genel ozeti
- `input\downloaded-archive.txt`: tekrar indirme engeli arsivi

## 6) Reset ve temiz kurulum

Temiz baslangic icin:
- `RESET.bat` calistir

Sifirlananlar:
- `input` (tamami)
- `output` (tamami)
- tum ana rapor dosyalari

Ardindan bos `input` ve `output` klasorleri tekrar olusturulur.

## 7) Dikkat edilmesi gerekenler

- `instagram-links.txt` bos olmamali.
- Internet baglantisi stabil olmali.
- Instagram bazi linklerde login/cookie isteyebilir (`rate-limit` veya `login required`).
- Bu durumda link bazli hata alinabilir; diger linkler yine islenir.
- `EncoderMode=auto` ile GPU sorununda CPU'ya dusus saglanir.

## 8) Sik gorulen mesajlar

- `already_downloaded` / `Atlandi`:
  - Hata degil, duplicate engelleme calisiyor.
- `Specified rc mode is deprecated`:
  - FFmpeg/NVENC uyari mesaji, genelde kritik degil.
- `Non-monotonic DTS`:
  - Zaman damgasi uyari mesaji; cogu durumda output olusur.

## 9) Sorun giderme kisa listesi

1. `download-report.csv` icinde `status=error` satirlarini kontrol et.
2. `process-report.csv` icinde son hatali ciftin `error` alanini kontrol et.
3. Yeni cihazda bir kez `RUN.bat` -> `E` ile kurulum yap.
4. Gerekirse `RESET.bat` ile temizleyip tekrar calistir.
