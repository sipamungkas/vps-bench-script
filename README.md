# vps-bench-script

Tooling untuk benchmark VPS dengan [YABS.sh](https://github.com/mattfoley/yabs) dan
[bench.sh](https://github.com/Teddysun/bench.sh), lalu mengubah hasilnya menjadi
JSON untuk situs [astro-vps-bench](https://github.com/sipamungkas/astro-vps-bench).

Repo ini adalah rumah kanonik untuk skripnya, supaya URL `curl` tidak bergantung
pada repo situs. Isi `tools/` dan `tests/` di sini identik dengan yang ada di
`astro-vps-bench`.

## Mulai cepat

Jalankan YABS.sh lalu bench.sh di satu host, dan dapatkan JSON + laporan
Markdown. Tidak perlu clone repo:

```bash
curl -fsSL https://raw.githubusercontent.com/sipamungkas/vps-bench-script/main/tools/vps-bench-standalone \
  | bash -s -- vps-saya --slug nevacloud-nvme-jkt
```

Itu saja. Metadata paket (harga, lokasi, provider, link affiliate, tag)
sengaja tidak ada di perintah — kolomnya kosong di JSON, diisi manual nanti.
Hasil benchmark-nya sendiri sudah lengkap.

Butuh di komputer lokal: `bash`, `jq`, `curl`, `ssh`.
Butuh di server: `curl` dan `bash` (YABS.sh mengunduh dependensinya sendiri).

Total 20-35 menit. Jalankan YABS.sh lebih dulu, baru bench.sh, supaya keduanya
tidak saling berebut CPU dan skewanya mengacaukan angka.

## Keluaran

| Ke mana | Isi |
|---|---|
| `./bench-results/<slug>/<stempel>/<slug>.json` | data untuk `src/data/vps/` |
| `./bench-results/<slug>/<stempel>/<slug>.md` | laporan gabungan: paket, ringkasan, YABS (termasuk iperf3), bench.sh (termasuk speedtest.net) |
| `./bench-results/<slug>/<stempel>/yabs.txt` `benchsh.txt` | output mentah |
| stdout | ringkasan singkat + lokasi berkas |
| stderr | progres dan perintah `cp` siap pakai |

stdout sengaja bukan JSON, supaya tidak pernah ter-redirect ke `.json` berisi
teks. Repo `astro-vps-bench` yang aktif juga tidak pernah disentuh:

```bash
cp bench-results/<slug>/<stempel>/<slug>.json  src/data/vps/
mkdir -p src/data/raw/<slug>
cp bench-results/<slug>/<stempel>/{yabs,benchsh}.txt src/data/raw/<slug>/
pnpm build
```

Kalau metadata memang mau diisi sekalian lewat perintah, flag-nya tetap ada
(`--title`, `--provider`, `--price`, `--tag`, ...). Lihat tabel di bawah.

## Opsi

| Opsi | Fungsi |
|---|---|
| `--slug <s>` | Nama file JSON. Kalau kosong, diturunkan dari nama host |
| `--only-parse <dir>` | Pakai berkas mentah yang sudah ada, tanpa SSH |
| `--skip-yabs` / `--skip-bench` | Jangan jalankan salah satunya |
| `-o <dir>` | Folder keluaran (default `./bench-results`) |

Metadata opsional: `--title`, `--provider`, `--location`, `--price`,
`--currency`, `--cpu-cores`, `--ram-gb`, `--storage-gb`, `--bandwidth-tb`,
`--storage-type`, `--virtualization`, `--status`, `--affiliate`,
`--last-updated`, dan `--tag` (bisa diulang). Semua juga bisa lewat env:
`VBENCH_TITLE`, `VBENCH_PROVIDER`, `VBENCH_LOCATION`, `VBENCH_PRICE`,
`VBENCH_CURRENCY`, `VBENCH_CPU_CORES`, `VBENCH_RAM_GB`, `VBENCH_STORAGE_GB`,
`VBENCH_STORAGE_TYPE`, `VBENCH_BANDWIDTH_TB`, `VBENCH_VIRTUALIZATION`,
`VBENCH_STATUS`, `VBENCH_AFFILIATE`, `VBENCH_LAST_UPDATED`.

Kalau output mentahnya sudah ada di komputer lokal, tidak perlu SSH lagi:

```bash
./tools/vps-bench-standalone --only-parse <folder> --slug <slug>
```

## Kenapa parser-nya tidak ditulis ulang di skrip standalone

`tools/vps-bench-standalone` mengunduh `tools/lib/bench_parse.sh` dan
`tools/lib/astro_data.sh` dari repo ini lalu mem-`-source`-nya, bukan
menyalin logika jq-nya. Alasannya hanya ada satu implementasi parser.

Dua salinan akan bebas berbeda secara diam-diam, dan parser yang diam-diam
tidak sama dengan yang dipakai membangun data situs jauh lebih berbahaya
daripada tidak punya skrip sama sekali: hasilnya terlihat masuk akal tapi
tidak bisa dipercaya.

Untuk penggunaan offline, arahkan ke salinan lokal:

```bash
VBENCH_LIB_DIR=tools/lib ./tools/vps-bench-standalone ...
```

Ganti target repo/ref dengan `VBENCH_REPO` dan `VBENCH_REF`.

## Kalau tidak bisa lewat SSH

Kirim skrip ke server, ambil hasilnya, lalu parse di lokal:

```bash
./tools/vps-bench import slug-vps --yabs hasil-yabs.txt
./tools/vps-bench yabs-parse hasil-yabs.txt -o /tmp/cek   # JSON + Markdown
```

## Perintah lengkap

`tools/vps-bench` adalah CLI multi-perintah untuk dipakai di dalam clone repo:

| Perintah | Fungsi |
|---|---|
| `vps-bench yabs <host>` | Jalankan YABS.sh lewat SSH |
| `vps-bench bench <host>` | Jalankan bench.sh lewat SSH |
| `vps-bench import <slug> --yabs <file>` | Gabungkan hasil ke data Astro |
| `vps-bench yabs-parse <file>` | Parse teks YABS → JSON + Markdown |
| `vps-bench bench-parse <file>` | Parse teks bench.sh → JSON + Markdown |
| `vps-bench md <file.json>` | Render JSON menjadi Markdown |
| `vps-bench migrate` | Ubah data `.md` lama menjadi JSON + raw terpisah |

`import` bisa dijalankan ulang kapan saja. Metadata yang sudah ada (harga,
kategori, link affiliate) tidak tertimpa; hanya blok `benchmarks` dan
`summary` yang diperbarui.

## Isi repo

```
tools/vps-bench               CLI multi-perintah
tools/vps-bench-standalone    Entry point untuk curl | bash
tools/lib/bench_parse.sh      Parser YABS.sh dan bench.sh
tools/lib/astro_data.sh       Menyusun JSON sumber data situs
tools/lib/bench_render.sh     Render JSON menjadi Markdown (incl. laporan gabungan VPS)
tests/run_tests.sh            188 regression test
tests/fixture-*               Contoh output asli, untuk menangkap regresi format lama
```

## Test

```bash
bash tests/run_tests.sh
```

188 assertion, tidak perlu akses server maupun menjalankan Astro. Fixture
`tests/fixture-*-legacy.txt` berasal dari output **nyata** VPS supaya regresi
format lama (v2024/v2025) langsung ketahuan — nama label, satuan, dan format
IOPS di script itu berubah beberapa kali.

Test menulis ke folder sementara, bukan ke repo.

## Jebakan yang perlu diwaspadai

Menambah filter jq di `tools/lib/` harus tahu dua hal ini. Keduanya pernah
membuat data hilang **tanpa indication apa pun**:

1. **`capture()` yang tidak cocok tidak melempar error, tapi menghasilkan output
   kosong.** `try/catch` tidak menangkapnya. Objek yang salah satu field-nya nol
   output ikut jadi nol output, dan array menyusut diam-diam sehingga
   `[a, b]` menjadi `[]`. Di `bench_parse.sh` ini membuat seluruh tabel fio
   lenyap begitu ada satu nilai IOPS gagal diparse. Pakai `scan()` yang tidak
   pernah kosong, dan tutup tiap cabang dengan `// null`.

2. **`sub()` di jq 1.7 tidak memproses `\1` sebagai referensi grup.** Hasilnya
   string literal `\1`, yang gagal saat dikonversi ke angka. Untuk mengambil
   angka dari `"1.20 Gbits/sec"`, pakai `split(" ")` plus `tonumber`.

Butuh hanya `bash`, `jq`, `ssh`, `curl`. `bash 3.2` (default macOS) sudah
cukup. Tanpa dependensi Node atau Python.