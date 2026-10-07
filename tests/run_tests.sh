#!/usr/bin/env bash
# run_tests.sh - regression test untuk parser & renderer.
#
# Semua test memakai fixture tiruan dari tests/make_fixture.sh, bukan data
# benchmark sungguhan. Yang diuji adalah kebenarAN PARSING dan konsistensi
# skema, bukan angka performa.
#
# Jalankan: bash tests/run_tests.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$TESTS_DIR/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/bench-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

LULU=0; GAGAL=0
FAILED=""

ok()   { LULU=$((LULU + 1)); printf '  \033[32mok\033[0m   %s\n' "$1"; }
fail() { GAGAL=$((GAGAL + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAILED="${FAILED}${1}"$'\n'; }

# eq <label> <nilai_aktual> <nilai_harapan>
eq() {
    if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1 (dapat: '$2', harap: '$3')"; fi
}

#eq_jq <label> <filter_jq> <harapan> <file_json>
eq_jq() {
    local got
    got="$(jq -r "$2" "$4")"
    if [[ "$got" == "$3" ]]; then ok "$1"; else fail "$1 (dapat: '$got', harap: '$3')"; fi
}

section() { printf '\n\033[1m%s\033[0m\n' "$1"; }

command -v jq >/dev/null 2>&1 || { echo "butuh jq"; exit 1; }

bash "$TESTS_DIR/make_fixture.sh" all >/dev/null || { echo "gagal membuat fixture"; exit 1; }

BIN="$ROOT/tools/vps-bench"
chmod +x "$BIN"

# ---------------------------------------------------------------------------
section "sanitize escape sequence"
# shellcheck source=../tools/lib/bench_parse.sh
. "$ROOT/tools/lib/bench_parse.sh"

printf '\033[0;31;32mRedis\033[0m' >"$WORK/ansi.txt"
out="$(sanitize <"$WORK/ansi.txt")"
eq "warna dibuang" "$out" "Redis"

printf '\033[3J\033[H\033[2JTeks\r\nBaris\r\n' >"$WORK/clear.txt"
out="$(sanitize <"$WORK/clear.txt" | tr '\n' '|')"
eq "escape clear + CR dibuang" "$out" "Teks|Baris|"

# ---------------------------------------------------------------------------
section "hex_cari"
printf ' CPU Model          : Intel Xeon\n VM-x/AMD-V         : on\n' >"$WORK/kv.txt"
eq "label sederhana" "$(hex_cari "$WORK/kv.txt" 'CPU Model')" "Intel Xeon"
eq "label mengandung tanda hubung" "$(hex_cari "$WORK/kv.txt" 'VM-x/AMD-V')" "on"
eq "label tak ada -> kosong" "$(hex_cari "$WORK/kv.txt" 'Nope')" ""

# ---------------------------------------------------------------------------
section "bench.sh parser"
"$BIN" bench-parse "$TESTS_DIR/fixture-bench.txt" -o "$WORK/b" >/dev/null 2>&1
BJSON="$(ls "$WORK"/b/bench/*/*/result.json 2>/dev/null | head -1)"

if [[ -n "$BJSON" ]]; then ok "JSON terbentuk"; else fail "JSON terbentuk"; echo "lewati sisa test bench.sh"; fi

if [[ -n "$BJSON" ]]; then
eq_jq "schema"            '.schema' 'bench' "$BJSON"
eq_jq "versi script"      '.version' 'v2026-01-31' "$BJSON"
eq_jq "model CPU"         '.cpu.model' 'Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz' "$BJSON"
eq_jq "jumlah core"       '.cpu.cores' '2' "$BJSON"
eq_jq "frekuensi MHz"     '.cpu.freq_mhz' '2400' "$BJSON"
eq_jq "AES-NI"            '.cpu.aes' 'true' "$BJSON"
eq_jq "VM-x/AMD-V"        '.cpu.virt_flag' 'true' "$BJSON"
eq_jq "virtualization TIDAK tertukar dengan VM-x/AMD-V" '.system.virtualization' 'kvm' "$BJSON"
eq_jq "OS"                '.system.os' 'Ubuntu 22.04.4 LTS' "$BJSON"
eq_jq "kernel"            '.system.kernel' '5.15.0-119-generic' "$BJSON"
eq_jq "TCP congestion"    '.system.tcp_congestion' 'bbr' "$BJSON"
eq_jq "IPv4 online"       '.net.ipv4' 'true' "$BJSON"
eq_jq "IPv6 online"       '.net.ipv6' 'true' "$BJSON"
eq_jq "organisasi"        '.net.organization' 'AS64496 Example Hosting' "$BJSON"
eq_jq "lokasi"            '.net.location' 'Amsterdam / NL' "$BJSON"
eq_jq "I/O run1"          '.io_mb_s.run1' '612.44' "$BJSON"
eq_jq "I/O rata-rata"     '.io_mb_s.average' '600.77' "$BJSON"
eq_jq "runtime detik"     '.runtime_sec' '407' "$BJSON"
eq_jq "jumlah baris speedtest" '.speedtest | length' '10' "$BJSON"
eq_jq "node pertama"      '.speedtest[0].node' 'Speedtest.net' "$BJSON"
eq_jq "upload node 1"     '.speedtest[0].upload' '42.15 Mbit/s' "$BJSON"
eq_jq "download node 1"   '.speedtest[0].download' '168.72 Mbit/s' "$BJSON"
eq_jq "latensi node 1"    '.speedtest[0].latency' '8.44 ms' "$BJSON"
eq_jq "node ber-spasi"    '.speedtest[1].node' 'Los Angeles, US' "$BJSON"
eq_jq "baris Test failed dibuang" '[.speedtest[].node] | map(select(test("Sydney"))) | length' '0' "$BJSON"
eq_jq "upload & download TIDAK tertukar" '.speedtest[4].download' '189.63 Mbit/s' "$BJSON"

# CATATAN: glob di dalam assignment bash TIDAK diekspansi, jadi pakai ls.
MD="$(ls "$WORK"/b/bench/fixture-bench/*/result.md 2>/dev/null | head -1)"
eq "markdown terbentuk" "$([[ -n "$MD" && -s "$MD" ]] && echo ya || echo tidak)" "ya"
eq "markdown punya tabel iperf" "$(grep -c '^| Los Angeles, US |' $MD)" "1"
eq "markdown tidak punya Sydney" "$(grep -c 'Sydney' $MD || true)" "0"
fi

# ---------------------------------------------------------------------------
section "YABS parser - JSON native (-j)"
"$BIN" yabs-parse "$TESTS_DIR/fixture-yabs-json.txt" -o "$WORK/n" >/dev/null 2>&1
NJSON="$(ls "$WORK"/n/yabs/*/*/result.json 2>/dev/null | head -1)"

if [[ -n "$NJSON" ]]; then ok "JSON terbentuk"; else fail "JSON terbentuk"; fi

if [[ -n "$NJSON" ]]; then
eq_jq "schema"       '.schema' 'yabs' "$NJSON"
eq_jq "sumber json"  '.source' 'yabs-native-json' "$NJSON"
eq_jq "versi"        '.version' 'v2026-09-20' "$NJSON"
eq_jq "VM type di .os.vm" '.os.vm' 'KVM' "$NJSON"
eq_jq "arch"         '.os.arch' 'x86_64' "$NJSON"
eq_jq "fio block size" '.fio[0].bs' '4KiB' "$NJSON"
eq_jq "fio speed_r"  '.fio[0].speed_r' '90235' "$NJSON"
eq_jq "fio iops_r"   '.fio[0].iops_r' '23013' "$NJSON"
eq_jq "iperf busy"   '.iperf[2].send' 'busy' "$NJSON"
eq_jq "geekbench"    '.geekbench[0].version' '6' "$NJSON"
eq_jq "runtime"      '.runtime.elapsed' '552' "$NJSON"
fi

# ---------------------------------------------------------------------------
section "YABS parser - teks saja (fallback)"
"$BIN" yabs-parse "$TESTS_DIR/fixture-yabs.txt" -o "$WORK/t" >/dev/null 2>&1
TJSON="$(ls "$WORK"/t/yabs/*/*/result.json 2>/dev/null | head -1)"

if [[ -n "$TJSON" ]]; then ok "JSON terbentuk"; else fail "JSON terbentuk"; fi

if [[ -n "$TJSON" ]]; then
eq_jq "sumber json"      '.source' 'yabs-text-parse' "$TJSON"
eq_jq "distro"           '.os.distro' 'Ubuntu 22.04.4 LTS' "$TJSON"
eq_jq "VM type"          '.vm' 'KVM' "$TJSON"
eq_jq "uptime string"    '.uptime' '14 days, 6 hours, 21 minutes' "$TJSON"
eq_jq "core"             '.cpu.cores' '2' "$TJSON"
eq_jq "fio block size"   '.fio[0].bs' '4KiB' "$TJSON"
eq_jq "fio speed_r nyata" '.fio[0].speed_r' '90235' "$TJSON"
eq_jq "fio iops_rw nyata" '.fio[0].iops_rw' '20620' "$TJSON"
eq_jq "fio ada 2 block"  '.fio | length' '2' "$TJSON"
eq_jq "fio bukan array null" '(.fio | map(.speed_r) | map(select(. == null)) | length)' '0' "$TJSON"
eq_jq "iperf mode"       '.iperf[0].mode' 'IPv4' "$TJSON"
eq_jq "iperf 3 baris"    '.iperf | length' '3' "$TJSON"
eq_jq "iperf busy 0.00"  '.iperf[2].send' 'busy' "$TJSON"
eq_jq "geekbench array"  '.geekbench | type' 'array' "$TJSON"
eq_jq "geekbench versi"  '.geekbench[0].version' '6' "$TJSON"
eq_jq "geekbench single" '.geekbench[0].single' '812' "$TJSON"
eq_jq "runtime detik"    '.runtime_sec' '552' "$TJSON"
fi

# ---------------------------------------------------------------------------
section "YABS parser - format LAMA (v2025-04-20)"
# Fixture ini output NYATA dari VPS, bentuknya berbeda dari versi sekarang:
#   - baris fio "Total", bukan "Mixed"
#   - block size di DUA grup (4k/64k lalu 512k/1m), bukan satu grup
#   - IOPS ditulis ringkas: (44.3k), (738) - bukan (23013 iops)
#   - satuan GB/s
# Parser versi lama dibuat gagal total oleh bentuk-bentuk ini.
"$BIN" yabs-parse "$TESTS_DIR/fixture-yabs-legacy.txt" -o "$WORK/l" >/dev/null 2>&1
LJSON="$(ls "$WORK"/l/yabs/*/*/result.json 2>/dev/null | head -1)"

if [[ -n "$LJSON" ]]; then ok "JSON terbentuk"; else fail "JSON terbentuk"; fi

if [[ -n "$LJSON" ]]; then
eq_jq "versi diambil dari banner"  '.version' 'v2025-04-20' "$LJSON"
eq_jq "distro"                    '.os.distro' 'Ubuntu 24.04 LTS' "$LJSON"
eq_jq "VM type"                   '.vm' 'KVM' "$LJSON"
eq_jq "4k ikut terbaca"           '.fio[0].bs' '4k' "$LJSON"
eq_jq "semua 4 block size terbaca" '.fio | length' '4' "$LJSON"
eq_jq "block size terakhir"       '.fio[3].bs' '1m' "$LJSON"
eq_jq "IOPS ringkas 44.3k -> 44300" '.fio[0].iops_r' '44300' "$LJSON"
eq_jq "IOPS bulat 738 tetap 738"    '.fio[3].iops_r' '738' "$LJSON"
eq_jq "IOPS ringkas 1.9k -> 1900"  '.fio[2].iops_r' '1900' "$LJSON"
eq_jq "baris Total jadi speed_rw"  '.fio[0].speed_rw' '363510' "$LJSON"
eq_jq "GB/s dikonversi ke KBps"    '.fio[1].speed_r' '1509949' "$LJSON"
eq_jq "tidak ada IOPS null"        '[.fio[].iops_r] | map(select(. == null)) | length' '0' "$LJSON"
eq_jq "tidak ada speed null"       '[.fio[].speed_r] | map(select(. == null)) | length' '0' "$LJSON"
eq_jq "iperf 7 IPv4 + 7 IPv6"      '.iperf | length' '14' "$LJSON"
eq_jq "mode IPv4"                  '.iperf[0].mode' 'IPv4' "$LJSON"
eq_jq "mode IPv6 terdeteksi"       '.iperf[7].mode' 'IPv6' "$LJSON"
eq_jq "ISP dari blok ISO"          '.ip_info.isp' 'PT Deneva' "$LJSON"
eq_jq "negatif tidak jadi null"    '.geekbench | length' '0' "$LJSON"
fi

# ---------------------------------------------------------------------------
section "bench.sh parser - format LAMA (v2025-05-08)"
# Bentuk berbeda dari versi sekarang:
#   - "Total Mem" bukan "Total RAM", "TCP CC" bukan "TCP Congestion Ctrl"
#   - "System uptime" dan "Load average" huruf kecil
#   - satuan speedtest "Mbps", bukan "Mbit/s"
#   - tabel speedtest punya baris header
"$BIN" bench-parse "$TESTS_DIR/fixture-bench-legacy.txt" -o "$WORK/bl" >/dev/null 2>&1
BLJSON="$(ls "$WORK"/bl/bench/*/*/result.json 2>/dev/null | head -1)"

if [[ -n "$BLJSON" ]]; then ok "JSON terbentuk"; else fail "JSON terbentuk"; fi

if [[ -n "$BLJSON" ]]; then
eq_jq "versi"            '.version' 'v2025-05-08' "$BLJSON"
eq_jq "Total Mem terbaca"  '.mem.ram' '960.7 MB (288.4 MB Used)' "$BLJSON"
eq_jq "System uptime"      '.system.uptime' '0 days, 0 hour 4 min' "$BLJSON"
eq_jq "Load average"       '.system.load_average' '0.00, 0.00, 0.00' "$BLJSON"
eq_jq "TCP CC"             '.system.tcp_congestion' 'cubic' "$BLJSON"
eq_jq "GB/s dinormalkan ke MB/s" '.io_mb_s.run1' '5529.60' "$BLJSON"
eq_jq "rata-rata tetap MB/s"     '.io_mb_s.average' '5700.30' "$BLJSON"
eq_jq "speedtest terbaca"  '.speedtest | length' '7' "$BLJSON"
eq_jq "baris header dibuang" '[.speedtest[].node] | map(select(test("Node"))) | length' '0' "$BLJSON"
eq_jq "satuan Mbps"        '.speedtest[0].upload' '685.24 Mbps' "$BLJSON"
eq_jq "upload/download tidak tertukar" '.speedtest[1].download' '495.07 Mbps' "$BLJSON"
eq_jq "node ber-spasi + koma" '.speedtest[1].node' 'Paris, FR' "$BLJSON"
eq_jq "organisasi"          '.net.organization' 'AS138115 PT Deneva' "$BLJSON"
fi

# ---------------------------------------------------------------------------
section "lapisan Astro: slug, provider, frontmatter"
# shellcheck source=../tools/lib/astro_data.sh
. "$ROOT/tools/lib/astro_data.sh"

eq "slug dari judul ber-spasi" "$(hex_slug 'Nevacloud NVME Jakarta 2')" "nevacloud-nvme-jakarta-2"
eq "slug dari nama file"      "$(hex_slug 'onidel-4c-8g-singapore')" "onidel-4c-8g-singapore"
eq "provider dipisah"         "$(hex_pisah_provider 'Nevacloud (PT Deneva)')" "Nevacloud|PT Deneva"
eq "provider tanpa kurung"    "$(hex_pisah_provider 'Onidel')" "Onidel|"

VPS_DATA_DIR="$WORK/data/vps"; export VPS_DATA_DIR
VPS_RAW_DIR="$WORK/data/raw";  export VPS_RAW_DIR
LEGACY_DIR="$WORK/legacy";     export LEGACY_DIR
mkdir -p "$LEGACY_DIR"
cp "$TESTS_DIR/fixture-legacy.md" "$LEGACY_DIR/contoh-vps-2c-4g.md"

hex_md_lama "$LEGACY_DIR/contoh-vps-2c-4g.md" "$WORK/md" || fail "md lama terbaca"
eq "judul"        "$(jq -r '.title' "$WORK/md.meta.json")" "Contoh VPS NVMe 2"
eq "harga angka"  "$(jq -r '.price_monthly' "$WORK/md.meta.json")" "125000"
eq "core angka"   "$(jq -r '.cpu_cores' "$WORK/md.meta.json")" "2"
eq "affiliate tanpa tanda kutip" "$(jq -r '.affiliate_link' "$WORK/md.meta.json")" "https://contoh.id/buy?ref=1"
eq "tags jadi 3 item" "$(jq -r '.tags | length' "$WORK/md.meta.json")" "3"
eq "tag pertama"   "$(jq -r '.tags[0]' "$WORK/md.meta.json")" "KVM"
eq "raw YABS tidak ikut jadi metadata" "$(jq -r 'has("raw_yabs_output")' "$WORK/md.meta.json")" "false"
eq "blok raw YABS terpisah" "$(grep -c 'Yet-Another-Bench-Script' "$WORK/md.yabs.txt")" "1"
eq "blok raw bench terpisah" "$(grep -c 'A Bench.sh Script By Teddysun' "$WORK/md.benchsh.txt")" "1"
eq "indent blok raw dibuang" "$(grep -c '^  #' "$WORK/md.yabs.txt" || true)" "0"

# ---------------------------------------------------------------------------
section "lapisan Astro: import menghasilkan JSON"
"$ROOT/tools/vps-bench" import contoh-vps-2c-4g \
    --yabs "$WORK/md.yabs.txt" --benchsh "$WORK/md.benchsh.txt" \
    --title "Contoh VPS NVMe 2" \
    --provider "Contoh Cloud (PT Contoh Nusantara)" \
    --location "Jakarta, Indonesia" --price 125000 --currency IDR \
    --cpu-cores 2 --ram-gb 4 --storage-gb 60 --storage-type NVMe \
    --bandwidth-tb 3 --virtualization KVM --status Available \
    --affiliate "https://contoh.id/buy?ref=1" \
    --tag KVM --tag Indonesia --tag NVMe >/dev/null 2>&1

IMPORTED="$VPS_DATA_DIR/contoh-vps-2c-4g.json"
if [[ -s "$IMPORTED" ]]; then ok "berkas JSON terbentuk"; else fail "berkas JSON terbentuk"; fi

if [[ -s "$IMPORTED" ]]; then
eq_jq "slug"            '.slug' 'contoh-vps-2c-4g' "$IMPORTED"
eq_jq "provider dipisah menjadi kategori" '.provider' 'Contoh Cloud' "$IMPORTED"
eq_jq "badan usaha terpisah" '.provider_legal' 'PT Contoh Nusantara' "$IMPORTED"
eq_jq "judul"           '.title' 'Contoh VPS NVMe 2' "$IMPORTED"
eq_jq "harga"           '.price_monthly' '125000' "$IMPORTED"
eq_jq "mata uang"       '.currency' 'IDR' "$IMPORTED"
eq_jq "tag"             '.tags | length' '3' "$IMPORTED"
eq_jq "fio 4 block"     '.benchmarks.yabs.fio | length' '4' "$IMPORTED"
eq_jq "IOPS 134k jadi angka" '.benchmarks.yabs.fio[0].iops_r' '134000' "$IMPORTED"
eq_jq "iperf 3 baris"   '.benchmarks.yabs.iperf | length' '3' "$IMPORTED"
eq_jq "busy jadi busy"  '.benchmarks.yabs.iperf[2].recv' 'busy' "$IMPORTED"
eq_jq "geekbench single" '.benchmarks.yabs.geekbench[0].single' '1560' "$IMPORTED"
eq_jq "speedtest 3 baris" '.benchmarks.benchsh.speedtest | length' '3' "$IMPORTED"
eq_jq "GB/s jadi MB/s"  '.benchmarks.benchsh.io_mb_s.run1' '3174.40' "$IMPORTED"
eq_jq "raw file yabs dicatat"   '.benchmarks.yabs.raw_file' 'yabs.txt' "$IMPORTED"
eq_jq "raw file bench dicatat"  '.benchmarks.benchsh.raw_file' 'benchsh.txt' "$IMPORTED"
eq_jq "summary geekbench SC" '.summary.geekbench_single' '1560' "$IMPORTED"
eq_jq "summary max iops"   '.summary.max_iops' '265000' "$IMPORTED"
eq_jq "summary max read"   '.summary.max_read_mb_s' '1894.4' "$IMPORTED"
eq_jq "summary dd avg"     '.summary.dd_avg_mb_s' '3018.4' "$IMPORTED"
# 1.20 Gbit = 1200 Mbit, jadi harus menang melawan 610 Mbit
eq_jq "summary iperf terbaik (satuan awareness)" '.summary.best_iperf_send' '1.20 Gbits/sec' "$IMPORTED"
eq_jq "summary download terbaik" '.summary.speedtest_best_download' '1120.55 Mbps' "$IMPORTED"
eq "raw yabs tersalin"   "$([[ -s "$VPS_RAW_DIR/contoh-vps-2c-4g/yabs.txt" ]] && echo ya || echo tidak)" "ya"
eq "raw bench tersalin"  "$([[ -s "$VPS_RAW_DIR/contoh-vps-2c-4g/benchsh.txt" ]] && echo ya || echo tidak)" "ya"
eq "JSON tidak memuat teks mentah" "$(jq -r 'tostring | contains("Yet-Another-Bench-Script")' "$IMPORTED")" "false"
fi

# Metadata manual harus bertahan saat benchmark di-import ulang
section "import ulang tidak menimpa metadata manual"
"$ROOT/tools/vps-bench" import contoh-vps-2c-4g \
    --yabs "$WORK/md.yabs.txt" >/dev/null 2>&1
eq_jq "harga tetap"    '.price_monthly' '125000' "$IMPORTED"
eq_jq "affiliate tetap" '.affiliate_link' 'https://contoh.id/buy?ref=1' "$IMPORTED"
eq_jq "provider tetap"  '.provider' 'Contoh Cloud' "$IMPORTED"
eq_jq "benchmarks tetap ada" '.benchmarks.yabs.fio | length' '4' "$IMPORTED"

# ---------------------------------------------------------------------------
section "konsistensi skema: jalur -j vs jalur teks"
if [[ -n "$NJSON" && -n "$TJSON" ]]; then
for k in fio iperf geekbench; do
    if diff <(jq -S ".$k" "$NJSON") <(jq -S ".$k" "$TJSON") >/dev/null 2>&1; then
        ok ".$k identik di kedua jalur"
    else
        fail ".$k berbeda antara jalur -j dan jalur teks"
        diff <(jq -S ".$k" "$NJSON") <(jq -S ".$k" "$TJSON") | sed 's/^/       /'
    fi
done
else
fail "perbandingan jalur (JSON kurang)"
fi

# ---------------------------------------------------------------------------
section "renderer"
if [[ -n "$NJSON" ]]; then
MDN="$WORK/n/yabs/fixture-yabs-json"/*/result.md
eq "RAM dihitung ke GiB"  "$(grep -F '| RAM | 4 GiB |' $MDN | wc -l | tr -d ' ')" "1"
eq "Disk 80 GiB"          "$(grep -F '| Disk | 80 GiB |' $MDN | wc -l | tr -d ' ')" "1"
eq "bukan 81920 TiB"      "$(grep -c '81920 TiB' $MDN || true)" "0"
eq "uptime jadi hari"     "$(grep -c '| Uptime | 14d' $MDN)" "1"
eq "waktu dirapikan"      "$(grep -c 'Parsed at: 2026-10-07 03:14:52' $MDN)" "1"
eq "runtime jadi menit"   "$(grep -c 'Runtime: 9m 12s' $MDN)" "1"
eq "tabel iperf ada"      "$(grep -c '| iPerf | Warsaw, Poland (10G) |' $MDN)" "1"
eq "link geekbench"       "$(grep -c '\[link\](https://browser.geekbench.com' $MDN)" "1"
eq "judul UTC benar"      "$(grep -c 'UTC$' $MDN)" "1"
fi

# md harus bisa dipakai ulang pada JSON yang sama
if [[ -n "$BJSON" ]]; then
cp "$BJSON" "$WORK/lagi.json"
out="$("$BIN" md "$WORK/lagi.json")"
eq "perintah md menulis berkas" "$([[ -f "$out" ]] && echo ya || echo tidak)" "ya"

# idempoten: render dua kali dari JSON sama, abaikan baris timestamp "Generated"
"$BIN" md "$WORK/lagi.json" >/dev/null 2>&1
cp "$out" "$WORK/render1.md"
"$BIN" md "$WORK/lagi.json" >/dev/null 2>&1
if diff <(grep -v '^Generated:' "$WORK/render1.md") \
        <(grep -v '^Generated:' "$WORK/lagi.md") >/dev/null 2>&1; then
    ok "md idempoten antar render"
else
    fail "md berubah antar render dari JSON yang sama"
fi
fi

# ---------------------------------------------------------------------------
section "lhs_error"
out="$("$BIN" nonsense 2>&1 || true)"
eq "perintah tak dikenal ditolak" "$(printf '%s' "$out" | grep -c 'tidak dikenal')" "1"

out="$("$BIN" bench-parse /tmp/tidak-ada-xyz.txt 2>&1 || true)"
eq "berkas tak ada ditolak" "$(printf '%s' "$out" | grep -c 'tidak ditemukan')" "1"

out="$("$BIN" --help 2>&1 || true)"
eq "help tersedia" "$(printf '%s' "$out" | grep -c 'PERINTAH')" "1"

# ---------------------------------------------------------------------------
section "ssh gagal ditangani rapi"
# host yang tidak bisa diresolv -> harus keluar dengan pesan jelas, bukan menggantung
out="$(BENCH_EXPORT_SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=5" \
        "$BIN" yabs host-tidak-ada-xyz-abc123 -o "$WORK/ssh" 2>&1)"
eq "keluar dengan kode bukan nol" "$?" "1"
eq "pesan ssh ikut ditampilkan" "$(printf '%s' "$out" | grep -c 'Could not resolve hostname\|Connection refused\|Permission denied')" "1"
eq "tidak ada JSON palsu dibuat" "$(ls "$WORK"/ssh/yabs/*/*/result.json 2>/dev/null | wc -l | tr -d ' ')" "0"
eq "log error ssh tersimpan" "$(ls "$WORK"/ssh/yabs/*/*/ssh.err 2>/dev/null | wc -l | tr -d ' ')" "1"

# ---------------------------------------------------------------------------
section "laporan gabungan VPS (json + md)"
SA="$ROOT/tools/vps-bench-standalone"
mkdir -p "$WORK/mentah"
cp "$TESTS_DIR/fixture-yabs.txt" "$WORK/mentah/yabs.txt"
cp "$TESTS_DIR/fixture-bench.txt" "$WORK/mentah/benchsh.txt"

out="$(VBENCH_LIB_DIR="$ROOT/tools/lib" "$SA" --only-parse "$WORK/mentah" \
        --slug uji-singkat -o "$WORK/sa" 2>/dev/null)"
eq "perintah minimal jalan tanpa metadata" "$?" "0"
eq "stdout bukan JSON" "$(printf '%s' "$out" | jq -e . >/dev/null 2>&1 && echo json || echo teks)" "teks"

# stempel waktu di tengah path, jadi path-nya dicari dulu. Glob di dalam
# assignment tidak pernah di-expand.
SJ="$(ls "$WORK"/sa/uji-singkat/*/uji-singkat.json 2>/dev/null | head -1)"
SM="$(ls "$WORK"/sa/uji-singkat/*/uji-singkat.md 2>/dev/null | head -1)"
eq "JSON terbentuk" "$([[ -s $SJ ]] && echo ya || echo tidak)" "ya"
eq "Markdown terbentuk" "$([[ -s $SM ]] && echo ya || echo tidak)" "ya"

# metadata kosong harus jadi null/[] di JSON, bukan string kosong
eq_jq "title jatuh ke slug"    '.title'     'uji-singkat' "$SJ"
eq_jq "harga null"             '.price_monthly' 'null'   "$SJ"
eq_jq "affiliate null"         '.affiliate_link' 'null'  "$SJ"
eq_jq "tags kosong"            '.tags | length' '0'      "$SJ"
eq_jq "lokasi null"            '.location'   'null'      "$SJ"
eq_jq "summary tetap terisi"   '.summary.geekbench_single != null' 'true' "$SJ"

# markdown gabungan: paket + ringkasan + iperf3 + speedtest
eq "md ada judul"          "$(grep -c '^# uji-singkat$' "$SM")" "1"
eq "md ada tabel paket"    "$(grep -c '^| Harga bulanan |' "$SM")" "1"
eq "md ada ringkasan"      "$(grep -c '^## Ringkasan$' "$SM")" "1"
eq "md ada bagian YABS"    "$(grep -c '^## YABS$' "$SM")" "1"
eq "md ada bagian bench"   "$(grep -c '^## bench.sh$' "$SM")" "1"
eq "md memuat iperf3"      "$(grep -c '^| iPerf | Warsaw, Poland (10G) |' "$SM")" "1"
eq "md memuat speedtest"   "$(grep -c '^| Los Angeles, US |' "$SM")" "1"
eq "hanya satu Generated"  "$(grep -c '^Generated: ' "$SM")" "1"
eq "tidak ada judul ganda" "$(grep -c '^# Benchmark Report' "$SM")" "0"

# slug boleh lewat dari nama host, tapi host tetap wajib
mkdir -p "$WORK/mentah2"
cp "$TESTS_DIR/fixture-bench.txt" "$WORK/mentah2/benchsh.txt"
VBENCH_LIB_DIR="$ROOT/tools/lib" "$SA" --only-parse "$WORK/mentah2" \
    --slug tetap-slip -o "$WORK/sa2" >/dev/null 2>&1
eq "hanya benchsh tetap bisa" "$(ls "$WORK"/sa2/tetap-slip/*/tetap-slip.md 2>/dev/null | wc -l | tr -d ' ')" "1"

# bagian yang tidak ada tidak boleh muncul sebagai judul kosong
mkdir -p "$WORK/mentah3"
cp "$TESTS_DIR/fixture-yabs.txt" "$WORK/mentah3/yabs.txt"
VBENCH_LIB_DIR="$ROOT/tools/lib" "$SA" --only-parse "$WORK/mentah3" \
    --slug yabs-saja -o "$WORK/sa3" >/dev/null 2>&1
SM3="$(ls "$WORK"/sa3/yabs-saja/*/yabs-saja.md 2>/dev/null | head -1)"
eq "bagian bench absen dihilangkan" "$(grep -c '^## bench.sh$' "$SM3" || true)" "0"
eq "bagian yabs tetap ada"          "$(grep -c '^## YABS$' "$SM3")" "1"

out="$(VBENCH_LIB_DIR="$ROOT/tools/lib" "$SA" --only-parse "$WORK/mentah" -o "$WORK/sa4" 2>&1)"
eq "tanpa --slug tetap jalan" "$?" "0"
eq "tanpa --slug diperingatkan" "$(printf '%s' "$out" | grep -c 'tanpa --slug')" "1"

# ---------------------------------------------------------------------------
section "folder keluaran tidak saling menimpa"
for i in 1 2; do
    "$BIN" bench-parse "$TESTS_DIR/fixture-bench.txt" -o "$WORK/coll" >/dev/null 2>&1
done
eq "dua hasil terpisah" "$(ls "$WORK"/coll/bench/*/*/result.json 2>/dev/null | wc -l | tr -d ' ')" "2"

# ---------------------------------------------------------------------------
printf '\n'
if [[ $GAGAL -eq 0 ]]; then
    printf '\033[32m%s lolos\033[0m, %s gagal\n' "$LULU" "$GAGAL"
    exit 0
else
    printf '\033[31m%s lolos\033[0m, \033[31m%s gagal\033[0m\n' "$LULU" "$GAGAL"
    printf '%s' "$FAILED" | while IFS= read -r f; do
        [[ -n "$f" ]] && printf '  - %s\n' "$f"
    done
    exit 1
fi