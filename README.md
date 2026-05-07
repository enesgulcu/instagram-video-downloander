# FFmpeg Instagram Pipeline

Instagram linklerinden video indirip ikili kombinasyonlarla yeni videolar ureten otomasyon projesi.

## Ne Yapar?

- `instagram-links.txt` icindeki Instagram URL'lerini okur.
- Videolari `input` klasorune indirir.
- Ayni icerigi tekrar indirmemek icin arsiv kontrolu yapar.
- Videolari 2'li gruplar halinde birlestirir.
- Sonuclari `output` klasorune yazar.

Her output videosunun olusum sirasi:
1. 1. videonun son 5 saniyesi
2. 1. videonun tamami
3. 2. videonun son 5 saniyesi
4. 2. videonun tamami

## Klasor Yapisi

- `RUN.bat` - ana calistirma dosyasi
- `RESET.bat` - tum calisma verisini sifirlama
- `start-run.ps1` - giris scripti
- `run-pipeline.ps1` - indirme + isleme orkestrasyonu
- `download-instagram.ps1` - indirme modulu
- `process-videos.ps1` - video birlestirme/isleme modulu
- `setup.ps1` - ffmpeg ve yt-dlp kurulum kontrolu
- `KULLANIM-REHBERI.md` - detayli Turkce kullanim dokumani

## Hizli Baslangic

1. `instagram-links.txt` dosyasini doldur.
2. `RUN.bat` calistir.
3. Kurulum sorusunda:
   - yeni cihazda `E`
   - kurulu sistemde `Enter`
4. Islem bitince `output` klasorunu kontrol et.

## Temiz Baslangic (Reset)

`RESET.bat` calistirildiginda:
- `input` ve `output` temizlenir
- log/rapor dosyalari temizlenir
- bos `input` ve `output` klasorleri tekrar olusturulur

## Log ve Rapor Dosyalari

- `download-report.csv`
- `process-report.csv`
- `run-summary.json`
- `pipeline-master-log.jsonl`
- `input/downloaded-archive.txt`
- `output/merge-notes.md` (cikti videosu + kaynak linkler + aciklamalar)

## Notlar

- Duplicate icerikler otomatik atlanir (`already_downloaded`).
- Instagram bazi URL'lerde login/cookie isteyebilir.
- Sistem stabilite odakli calisir; sorunlu ciftler loglanir, surec devam eder.

## Gereksinimler

- Windows + PowerShell
- `ffmpeg`
- `yt-dlp`

Kurulum adiminda (`E`) eksik araclar otomatik kurulabilir.
