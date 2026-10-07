#!/usr/bin/env bash
# bench_parse.sh - ubah output teks bench.sh / YABS.sh menjadi JSON terstruktur.
#
# sourced oleh bin/bench-export. Tidak meantik untuk dieksekusi langsung.
#
# CATATAN PENTING soal akurasi:
#   - YABS.sh punya JSON bawaan (flag -j / -w). Jalur itu dipakai sebagai
#     primary dan TIDAK melalui parser di file ini. Parser teks YABS di sini
#     hanya fallback untuk berkas .txt lama yang sudah tersimpan.
#   - bench.sh (Teddysun) tidak punya JSON sama sekali, jadi teksnya wajib
#     di-parse. Field diambil dari label literal yang dicetak script tersebut.
#
# Output warna: bench.sh dan YABS sama-sama memakai kode ANSI, dan bench.sh
# memanggil `clear` yang tetap menyalakan escape sequence walau stdout di-pipe.
# Semua teks dibersihkan dulu oleh sanitize() sebelum dibaca.

# Bersihkan ANSI escape sequence, carriage return, dan sisa kode clear-screen.
sanitize() {
    # stdin -> stdout
    if command -v perl >/dev/null 2>&1; then
        perl -pe 's/\e\][^\a\e]*(?:\a|\e\\)//g; s/\e\[[0-9;?]*[a-zA-Z]//g; s/\e[()#][0-9A-Za-z]//g; s/\r//g; s/\x{0C}//g'
    else
        sed -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' -e 's/\x1b[()#][0-9A-Za-z]//g' | tr -d '\r\014'
    fi
}

# Tulis teks bersih ke berkas sementara, kembalikan path-nya.
# sanitize_to <masukan> <keluaran>
sanitize_to() {
    sanitize <"$1" >"$2"
}

# Ambil nilai dari baris "Label : Value" berdasarkan label persis.
# Hex_cari <berkas_bersih> <label>
hex_cari() {
    awk -v k="$2" '
        {
            line = $0
            sub(/^[ \t]+/, "", line)
            pos = index(line, ":")
            if (pos > 0) {
                key = substr(line, 1, pos - 1)
                sub(/[ \t]+$/, "", key)
                if (key == k) {
                    val = substr(line, pos + 1)
                    sub(/^[ \t]+/, "", val)
                    sub(/[ \t]+$/, "", val)
                    print val
                    exit
                }
            }
        }' "$1"
}

# Program jq untuk mengubah sel fio mentah ("177.26 MB/s  (44.3k)") menjadi
# angka: kecepatan dinormalkan ke KBps, IOPS jadi angka penuh.
#
# PERINGATAN - jebakan jq yang pernah membuat tabel fio lenyap tanpa warning:
# `capture()` tidak melempar error ketika polanya tidak cocok; ia menghasilkan
# OUTPUT KOSONG. `try/catch` TIDAK menangkap itu (catch hanya untuk error
# sungguhan). Akibatnya objek yang salah satu field-nya nol output ikut
# menjadi nol output, dan array pun menyusut diam-diam - `[a, b]` menjadi `[]`.
# Seluruh tabel fio hilang begitu ada satu nilai yang gagal diparse.
#
# Karena itu di sini: pakai `scan()` yang selalu mengembalikan array, dan
# normalkan setiap cabang dengan `// null` supaya satu nilai pun tidak pernah
# hilang. Jangan pakai `capture` di file ini.
FIO_JQ='
def kb:
    ((. // "") | tostring | split(" ")) as $p
    | if ($p | length) < 2 then null
      else (($p[0] | tonumber?) // null) as $n
        | if $n == null then null
          else (({
                  "KiB": 1,       "KB": 1,       "KiB/s": 1,      "KB/s": 1,      "B/s": 1,
                  "MiB": 1024,    "MB": 1024,    "MiB/s": 1024,   "MB/s": 1024,
                  "GiB": 1048576, "GB": 1048576, "GiB/s": 1048576,"GB/s": 1048576,
                  "Kib": 1,       "Mib": 1024,   "Gib": 1048576,
                  "KiBps": 1,     "MiBps": 1024, "GiBps": 1048576
                }[$p[1] // ""]) // null) as $k
            | if $k == null then null else (($n * $k) | round) end
          end
        end;

# Ambil angka di dalam kurung. Dua format YABS harus ditangani:
#   (23013 iops)   angka penuh   -> 23013
#   (44.3k)       format ringkas -> 44300
def iops:
    (((. // "") | tostring) | [scan("\\([^)]*\\)")] | last // "") as $m
    | ($m | sub("^\\("; "") | sub("\\)$"; "")) as $t
    | ($t | test("[kK]$")) as $big
    | (($t | sub("[^0-9.].*$"; "") | tonumber?) // null) as $v
    | if    $v == null then null
      elif $big then (($v * 1000) | round)
      else ($v | round)
      end;

def cell($bs; $r; $w; $t):
    { bs: $bs,
      speed_r:  ($r | kb), iops_r:  ($r | iops),
      speed_w:  ($w | kb), iops_w:  ($w | iops),
      speed_rw: ($t | kb), iops_rw: ($t | iops),
      speed_units: "KBps" };

[ (.results // [])[] | cell(.bs; .r; .w; .t) ]
'

# Mencoba beberapa label sekaligus. Dipakai karena nama label berubah antar
# versi script: bench.sh v2025 memakai "Total Mem" dan "TCP CC", versi lebih
# baru memakai "Total RAM" dan "TCP Congestion Ctrl".
# Urutan = prioritas; label pertama yang ketemu dipakai.
# hex_cari_multi <berkas_bersih> <label1|label2|...>
hex_cari_multi() {
    local f="$1" rest="$2" l v
    while [[ -n "$rest" ]]; do
        l="${rest%%|*}"
        if [[ "$rest" == *"|"* ]]; then
            rest="${rest#*|}"
        else
            rest=""
        fi
        v="$(hex_cari "$f" "$l")"
        if [[ -n "$v" ]]; then
            printf '%s' "$v"
            return 0
        fi
    done
    return 1
}

# Normalkan laju disk ke MB/s supaya antar versi bisa dibandingkan.
# <angka> <satuan>  ->  JSON angka MB/s, atau null bila tidak bisa dibaca.
ke_mb_s() {
    local n="$1" u="$2" k
    if ! [[ "$n" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        printf 'null'
        return
    fi
    case "$u" in
        "B/s")               k=0.000000953674 ;;
        "KB/s"|"KiB/s")      k=0.0009765625 ;;
        "MB/s"|"MiB/s")      k=1 ;;
        "GB/s"|"GiB/s")      k=1024 ;;
        "TB/s")              k=1048576 ;;
        *)                   k=1 ;;
    esac
    awk -v n="$n" -v k="$k" 'BEGIN{printf "%.2f", n*k}'
}

# --- parser YABS.sh (teks) --------------------------------------------------
# Fungsi ini jalur fallback saja. Skema JSON ditiru persis dari kode YABS
# (lihat JSON_RESULT di yabs.sh) supaya bentuknya konsisten dengan -j.
# hex_yabs_teks <berkas_teks_mentah> <berkas_json_keluaran>
hex_yabs_teks() {
    local in="$1" out="$2" tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/yabs_parse.XXXXXX")"
    sanitize_to "$in" "$tmp" || return 1

    # Nilai sederhana dari blok "Basic System Information"
    local versi uptime proc cores freq aes ram swap disk distro kernel vm_type online
    versi="$(awk '
        /Yet-Another-Bench-Script/ { title = NR; next }
        # versi ada di baris SETELAH judul di banner, di tengah tanda pagar
        title && NR == title + 1 {
            s = $0
            gsub(/#/, "", s)
            # CATATAN: regex dengan alternasi "|" HANYA valid di awk kalau
            # targetnya variabel. gsub(/a|b/, "", "") memicu syntax error.
            gsub(/^[ \t]+/, "", s)
            gsub(/[ \t]+$/, "", s)
            if (s != "") print s
            exit
        }' "$tmp")"
    uptime="$(hex_cari "$tmp" 'Uptime')"
    proc="$(hex_cari "$tmp" 'Processor')"
    cores="$(hex_cari "$tmp" 'CPU cores')"
    distro="$(hex_cari "$tmp" 'Distro')"
    kernel="$(hex_cari "$tmp" 'Kernel')"
    vm_type="$(hex_cari "$tmp" 'VM Type')"
    ram="$(hex_cari "$tmp" 'RAM')"
    swap="$(hex_cari "$tmp" 'Swap')"
    disk="$(hex_cari "$tmp" 'Disk')"
    aes="$(hex_cari "$tmp" 'AES-NI')"
    online="$(hex_cari "$tmp" 'IPv4/IPv6')"

    # "4 @ 2400 MHz" -> jumlah core
    local n_core="null"
    [[ "$cores" =~ ^([0-9]+) ]] && n_core="${BASH_REMATCH[1]}"

    local b_ipv4="false" b_ipv6="false"
    case "$online" in
        *IPv4*|*"✓"*) b_ipv4="true" ;;
    esac
    case "$online" in
        *IPv6*|*"✓"*) b_ipv6="true" ;;
    esac

    # Ambil blok IPv4 & IPv6 lewat label yang hanya muncul di status online/offline.
    local st4 st6
    st4="$(hex_cari "$tmp" 'IPv4')"
    st6="$(hex_cari "$tmp" 'IPv6')"
    [[ "$st4" == *Offline* ]] && b_ipv4="false"
    [[ "$st6" == *Offline* ]] && b_ipv6="false"

    local aes_bool="null"
    case "$aes" in
        *Enabled*) aes_bool="true" ;;
        *Disabled*) aes_bool="false" ;;
    esac

    # --- iperf3: baris "Provider | Location | Send | Recv | Ping"
    local iperf_json
    iperf_json="$(
        awk '
            /iperf3 Network Speed Tests/ {
                inside = 1
                # "iperf3 Network Speed Tests (IPv4):" -> mode
                if (match($0, /\(IPv[46]\)/)) mode = substr($0, RSTART + 1, RLENGTH - 2)
                next
            }
            inside && /Geekbench/ { inside = 0 }
            inside {
                if (index($0, "|") == 0) next
                if ($0 ~ /Provider/) next
                n = split($0, a, "|")
                if (n < 5) next
                for (i = 1; i <= 5; i++) {
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i])
                }
                # buang baris pemisah "----- | ----- | ..." yang ikut terbaca
                if (a[1] ~ /^-+$/ || a[2] ~ /^-+$/ || a[3] ~ /^-+$/) next
                if (a[1] == "" || a[2] == "" || a[3] == "") next
                printf "%s\t%s\t%s\t%s\t%s\t%s\n", mode, a[1], a[2], a[3], a[4], a[5]
            }' "$tmp" |
        awk -F'\t' 'BEGIN{printf "["; first=1}
            {
                if (!first) printf ",";
                first = 0
                # YABS sendiri mengubah kecepatan 0.00 menjadi "busy" ketika
                # server iperf terlalu terbebani. Samakan perilakunya supaya
                # jalur teks dan jalur -j menghasilkan nilai yang sama.
                send = $4; recv = $5
                if (send == "" || send ~ /^0\.00/) send = "busy"
                if (recv == "" || recv ~ /^0\.00/) recv = "busy"
                m = ($1 == "" ? "null" : "\"" $1 "\"")
                printf "{\"mode\":%s,\"provider\":\"%s\",\"loc\":\"%s\",\"send\":\"%s\",\"recv\":\"%s\",\"latency\":\"%s\"}", \
                    m, $2, $3, send, recv, $6
            }
            END{printf "]"}'
    )"

    # --- fio -----------------------------------------------------------------
    # Tata letak teks YABS:
    #   Block Size | 4KiB  (IOPS) | 1MiB  (IOPS)
    #   Read       | 88.12 MB/s (23013 iops) | 412.55 MB/s (1025 iops)
    #   Write      | ...
    #   Mixed      | ...
    # Nilai kecepatan sengaja dikumpulkan utuh sebagai teks; konversi ke KBps
    # dan pemisahan IOPS dikerjakan jq di bawah, sehingga bentuk hasilnya sama
    # persis dengan JSON native -j.
    local fio_raw
    fio_raw="$(
        awk '
            /fio Disk Speed Tests/ { inside=1; next }
            inside && /iperf3|Geekbench|Basic System|dd Sequential/ { inside=0 }
            inside {
                if (index($0, "|") == 0) next
                n = split($0, a, "|")
                for (i = 1; i <= n; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i])

                # YABS bisa mencetak block size dalam DUA grup:
                #   Block Size | 4k (IOPS) | 64k (IOPS)
                #   ... Read/Write/Total ...
                #   Block Size | 512k (IOPS) | 1m (IOPS)
                #   ... Read/Write/Total ...
                # Jadi semua grup dikumpulkan, bukan cuma dua kolom pertama.
                if (a[1] == "Block Size") {
                    for (i = 2; i <= n; i++) {
                        split(a[i], q, " ")
                        if (q[1] != "" && q[1] !~ /^-+$/) bs[++nb] = q[1]
                    }
                    gstart = nb - n + 2
                    next
                }

                # Baris "Mixed" (YABS baru) dan "Total" (YABS lama) sama-sama
                # berarti campuran read+write. Mixed lebih spesifik, jadi kalau
                # keduanya muncul Mixed yang dipakai.
                k = tolower(a[1])
                if (k == "read" || k == "write" || k == "mixed" || k == "total") {
                    for (i = 2; i <= n; i++) {
                        if (a[i] == "" || a[i] ~ /^-+$/) continue
                        idx = gstart + (i - 2)
                        if (idx < 1 || idx > nb) continue
                        if (k == "read")         rr[idx] = a[i]
                        else if (k == "write")   ww[idx] = a[i]
                        else if (k == "mixed")   tt[idx] = a[i]
                        else if (tt[idx] == "")  tt[idx] = a[i]
                    }
                }
            }
            END {
                if (nb == 0) exit
                printf "{\"results\":["
                for (i = 1; i <= nb; i++) {
                    if (i > 1) printf ","
                    printf "{\"bs\":\"%s\",\"r\":\"%s\",\"w\":\"%s\",\"t\":\"%s\"}", \
                        bs[i], rr[i], ww[i], tt[i]
                }
                printf "]}"
            }' "$tmp"
    )"

    local fio_json="[]"
    if [[ -n "$fio_raw" ]]; then
        fio_json="$(
            printf '%s' "$fio_raw" | jq -c "$FIO_JQ"
        )"
    fi

    # --- Geekbench: "Geekbench 6 Benchmark Test:" lalu Single/Multi/Full
    # Dibentuk sebagai array supaya skemanya sama dengan JSON native -j.
    local gb_json
    gb_json="$(
        awk '
            /Geekbench [0-9]+ Benchmark Test:/ {
                ver = $2
                inside = 1
                next
            }
            inside && /YABS completed/ { inside = 0 }
            inside {
                n = split($0, a, "|")
                if (n < 2) next
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[1])
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[2])
                if (a[1] == "Single Core") single = a[2]
                else if (a[1] == "Multi Core") multi = a[2]
                else if (a[1] == "Full Test") url = a[2]
            }
            END {
                if (single == "" && multi == "" && url == "") exit
                printf "[{\"version\":%s,\"single\":%s,\"multi\":%s,\"url\":\"%s\"}]", \
                    (ver == "" ? "null" : ver), \
                    (single == "" ? "null" : single), \
                    (multi == "" ? "null" : multi), url
            }' "$tmp"
    )"
    [[ -z "$gb_json" ]] && gb_json="[]"

    local runtime="null"
    local secs
    secs="$(awk '/YABS completed in/ {
            if (match($0, /[0-9]+ min [0-9]+ sec/)) {
                s = substr($0, RSTART, RLENGTH)
                gsub(/[^0-9 ]/, "", s)
                split(s, p, " ")
                print p[1]*60 + p[2]
            } else if (match($0, /[0-9]+ sec/)) {
                s = substr($0, RSTART, RLENGTH)
                gsub(/[^0-9]/, "", s)
                print s
            }
        }' "$tmp" | head -1)"
    [[ -n "$secs" ]] && runtime="$secs"

    local mulai sekarang
    mulai="$(hex_cari "$tmp" 'Time')"

    # Blok "IPv4/IPv6 Network Information:" memuat ISP/ASN/lokasi. Labelnya
    # sama persis dengan yang dipakai YABS di JSON -j, jadi cukup hex_cari.
    local iso_isp iso_asn iso_org iso_loc iso_country
    iso_isp="$(hex_cari_multi "$tmp" 'ISP')"
    iso_asn="$(hex_cari_multi "$tmp" 'ASN')"
    iso_org="$(hex_cari_multi "$tmp" 'Host|Org')"
    iso_loc="$(hex_cari_multi "$tmp" 'Location')"
    iso_country="$(hex_cari_multi "$tmp" 'Country')"

    jq -n \
        --arg version "$versi" \
        --arg time "$mulai" \
        --arg arch "" \
        --arg distro "$distro" \
        --arg kernel "$kernel" \
        --arg uptime "$uptime" \
        --arg vm "$vm_type" \
        --argjson ipv4 "$b_ipv4" \
        --argjson ipv6 "$b_ipv6" \
        --arg model "$proc" \
        --argjson cores "$n_core" \
        --arg freq "$cores" \
        --argjson aes "$aes_bool" \
        --arg ram "$ram" \
        --arg swap "$swap" \
        --arg disk "$disk" \
        --argjson iperf "$iperf_json" \
        --argjson fio "$fio_json" \
        --argjson geekbench "$gb_json" \
        --argjson runtime "$runtime" \
        --arg isp "${iso_isp:-}" \
        --arg asn "${iso_asn:-}" \
        --arg org "${iso_org:-}" \
        --arg loc "${iso_loc:-}" \
        --arg country "${iso_country:-}" \
        '{
            schema: "yabs",
            source: "yabs-text-parse",
            version: (if $version == "" then null else $version end),
            time: (if $time == "" then null else $time end),
            os: { arch: null, distro: (if $distro == "" then null else $distro end),
                  kernel: (if $kernel == "" then null else $kernel end) },
            uptime: (if $uptime == "" then null else $uptime end),
            vm: (if $vm == "" then null else $vm end),
            net: { ipv4: $ipv4, ipv6: $ipv6 },
            cpu: { model: (if $model == "" then null else $model end),
                   cores: $cores, freq: (if $freq == "" then null else $freq end),
                   aes: $aes },
            mem: { ram: (if $ram == "" then null else $ram end),
                   swap: (if $swap == "" then null else $swap end),
                   disk: (if $disk == "" then null else $disk end) },
            iperf: $iperf,
            fio: $fio,
            geekbench: $geekbench,
            ip_info: (if $isp == "" and $asn == "" and $country == "" then null else {
                protocol: null,
                isp: (if $isp == "" then null else $isp end),
                asn: (if $asn == "" then null else $asn end),
                org: (if $org == "" then null else $org end),
                city: null,
                region: null,
                region_code: null,
                location: (if $loc == "" then null else $loc end),
                country: (if $country == "" then null else $country end)
            } end),
            runtime_sec: $runtime
        }' >"$out"

    rm -f "$tmp"
}

# --- parser bench.sh (Teddysun) ---------------------------------------------
# Labelled "Label : Value" persis seperti yang dicetak print_system_info().
# Tabel speedtest tidak punya header, jadi kolom dibaca posisional:
#   printf "%-18s%-18s%-20s%-12s" node, upload, download, latency
# (lihat speed_test() di bench.sh)
hex_bench_teks() {
    local in="$1" out="$2" tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/bench_parse.XXXXXX")"
    sanitize_to "$in" "$tmp" || return 1

    local versi cpu_model cores cache aes virt_flag virt_type disk ram swap uptime load os arch kernel tcp ip4ip6
    versi="$(hex_cari "$tmp" 'Version')"
    cpu_model="$(hex_cari "$tmp" 'CPU Model')"
    cores="$(hex_cari "$tmp" 'CPU Cores')"
    cache="$(hex_cari "$tmp" 'CPU Cache')"
    aes="$(hex_cari "$tmp" 'AES-NI')"
    virt_flag="$(hex_cari "$tmp" 'VM-x/AMD-V')"
    virt_type="$(hex_cari "$tmp" 'Virtualization')"
    disk="$(hex_cari "$tmp" 'Total Disk')"
    ram="$(hex_cari_multi "$tmp" 'Total RAM|Total Mem')"
    swap="$(hex_cari "$tmp" 'Total Swap')"
    uptime="$(hex_cari_multi "$tmp" 'System Uptime|System uptime')"
    load="$(hex_cari_multi "$tmp" 'Load Average|Load average')"
    os="$(hex_cari "$tmp" 'OS')"
    arch="$(hex_cari "$tmp" 'Arch')"
    kernel="$(hex_cari "$tmp" 'Kernel')"
    tcp="$(hex_cari_multi "$tmp" 'TCP Congestion Ctrl|TCP CC')"
    ip4ip6="$(hex_cari "$tmp" 'IPv4/IPv6')"
    local org location region
    org="$(hex_cari "$tmp" 'Organization')"
    location="$(hex_cari "$tmp" 'Location')"
    region="$(hex_cari "$tmp" 'Region')"

    local n_core="null" freq="null"
    if [[ "$cores" =~ ^([0-9]+)[[:space:]]*@\ *([0-9.]+) ]]; then
        n_core="${BASH_REMATCH[1]}"
        freq="${BASH_REMATCH[2]}"
    elif [[ "$cores" =~ ^([0-9]+) ]]; then
        n_core="${BASH_REMATCH[1]}"
    fi

    local aes_bool="null" virt_bool="null"
    case "$aes" in *Enabled*) aes_bool="true" ;; *Disabled*) aes_bool="false" ;; esac
    case "$virt_flag" in *Enabled*) virt_bool="true" ;; *Disabled*) virt_bool="false" ;; esac

    local b4="false" b6="false"
    [[ "$ip4ip6" == *"✓"* || "$ip4ip6" == *"Online"* ]] && b4="true"
    if [[ "$ip4ip6" == */* ]]; then
        local bagian="${ip4ip6#*/}"
        [[ "$bagian" == *"✓"* || "$bagian" == *"Online"* ]] && b6="true"
    fi

    # I/O speed: "I/O Speed(1st run) : 512.83 MB/s"
    local io1 io2 io3 ioavg
    io1="$(hex_cari "$tmp" 'I/O Speed(1st run)')"
    io2="$(hex_cari "$tmp" 'I/O Speed(2nd run)')"
    io3="$(hex_cari "$tmp" 'I/O Speed(3rd run)')"
    ioavg="$(hex_cari "$tmp" 'I/O Speed(average)')"

    local elapsed="null" timestamp
    timestamp="$(hex_cari "$tmp" 'Timestamp')"
    local fin
    fin="$(hex_cari "$tmp" 'Finished in')"
    if [[ "$fin" =~ ([0-9]+)[[:space:]]*min[[:space:]]*([0-9]+)[[:space:]]*sec ]]; then
        elapsed=$(( ${BASH_REMATCH[1]} * 60 + ${BASH_REMATCH[2]} ))
    elif [[ "$fin" =~ ([0-9]+)[[:space:]]*sec ]]; then
        elapsed="${BASH_REMATCH[1]}"
    fi

    # --- tabel speedtest -----------------------------------------------------
    # Baris valid mengandung satuan Mbit/s/Gbit/s. Nama node mengandung spasi,
    # jadi kolom diambil dari kanan sesuai lebar printf.
    local st_json
    st_json="$(
        awk '
            # Satuan berubah antar versi bench.sh:
            #   versi baru  "168.72 Mbit/s"
            #   versi lama  "477.13 Mbps"
            # keduanya harus dikenali, kalau tidak tabelnya kosong total.
            /[KMG]bit\/s|[KMG]bps|[KMG]bits\/sec/ {
                line = $0
                # rapatkan spasi, lalu buang spasi di kedua ujung.
                # printf %-Ns menyisakan spasi di akhir baris; kalau tidak
                # dibuang, split() menambah field kosong terakhir dan seluruh
                # indeks kolom bergeser satu.
                gsub(/[[:space:]]+/, " ", line)
                gsub(/^ +| +$/, "", line)
                n = split(line, f, / /)
                # setiap baris selalu diakhiri 6 token:
                # <angka> <satuan> <angka> <satuan> <angka> <satuan>
                if (n < 7) next
                latu = f[n];   lat   = f[n-1]
                downu = f[n-2]; down = f[n-3]
                upu  = f[n-4]; up   = f[n-5]
                # validasi satuan: tanpa ini, baris header "Node Name Upload
                # Speed ..." ikut terambil dan kolom jadi kacau
                if (upu  !~ /^[KMG]bit\/s$|^[KMG]bps$|^[KMG]bits\/sec$/) next
                if (downu !~ /^[KMG]bit\/s$|^[KMG]bps$|^[KMG]bits\/sec$/) next
                if (latu !~ /^(ms|s)$/) next
                if (up !~ /^[0-9.]+$/ || down !~ /^[0-9.]+$/ || lat !~ /^[0-9.]+$/) next
                node = ""
                for (i = 1; i <= n-6; i++) node = node (i > 1 ? " " : "") f[i]
                if (node == "") next
                printf "%s\t%s %s\t%s %s\t%s %s\n", node, up, upu, down, downu, lat, latu
            }' "$tmp" |
        awk -F'\t' 'BEGIN{printf "["; first=1}
            {
                if (!first) printf ",";
                first = 0
                printf "{\"node\":\"%s\",\"upload\":\"%s\",\"download\":\"%s\",\"latency\":\"%s\"}", $1, $2, $3, $4
            }
            END{printf "]"}'
    )"

    local io1j io2j io3j ioavj
    # Field bernama io_mb_s, jadi satuan HARUS dinormalkan: versi lama
    # melaporkan "5.4 GB/s" sementara yang baru "612.44 MB/s".
    # Tanpa konversi, yang GB/s akan terlihat 1024x lebih kecil dari aslinya.
    io_num() {
        local v="$1" n u
        [[ -z "$v" ]] && { printf 'null'; return; }
        n="${v%% *}"
        if [[ "$v" == *" "* ]]; then u="${v#* }"; else u=""; fi
        ke_mb_s "$n" "$u"
    }
    io1j="$(io_num "$io1")"
    io2j="$(io_num "$io2")"
    io3j="$(io_num "$io3")"
    ioavj="$(io_num "$ioavg")"

    jq -n \
        --arg version "$versi" \
        --arg timestamp "$timestamp" \
        --arg model "$cpu_model" \
        --arg cores_raw "$cores" \
        --argjson cores "$n_core" \
        --argjson freq "$freq" \
        --arg cache "$cache" \
        --argjson aes "$aes_bool" \
        --argjson virt_flag "$virt_bool" \
        --arg disk "$disk" \
        --arg ram "$ram" \
        --arg swap "$swap" \
        --arg uptime "$uptime" \
        --arg load "$load" \
        --arg os "$os" \
        --arg arch "$arch" \
        --arg kernel "$kernel" \
        --arg tcp "$tcp" \
        --arg virtualization "$virt_type" \
        --argjson ipv4 "$b4" \
        --argjson ipv6 "$b6" \
        --arg org "$org" \
        --arg location "$location" \
        --arg region "$region" \
        --argjson io1 "$io1j" \
        --argjson io2 "$io2j" \
        --argjson io3 "$io3j" \
        --argjson ioavg "$ioavj" \
        --argjson elapsed "$elapsed" \
        --argjson speedtest "$st_json" \
        '{
            schema: "bench",
            source: "bench-text-parse",
            version: (if $version == "" then null else $version end),
            time: (if $timestamp == "" then null else $timestamp end),
            cpu: { model: (if $model == "" then null else $model end),
                   cores: $cores, cores_raw: (if $cores_raw == "" then null else $cores_raw end),
                   freq_mhz: $freq, cache: (if $cache == "" then null else $cache end),
                   aes: $aes, virt_flag: $virt_flag },
            mem: { ram: (if $ram == "" then null else $ram end),
                   swap: (if $swap == "" then null else $swap end),
                   disk: (if $disk == "" then null else $disk end) },
            system: { os: (if $os == "" then null else $os end),
                      arch: (if $arch == "" then null else $arch end),
                      kernel: (if $kernel == "" then null else $kernel end),
                      virtualization: (if $virtualization == "" then null else $virtualization end),
                      tcp_congestion: (if $tcp == "" then null else $tcp end),
                      uptime: (if $uptime == "" then null else $uptime end),
                      load_average: (if $load == "" then null else $load end) },
            net: { ipv4: $ipv4, ipv6: $ipv6,
                   organization: (if $org == "" then null else $org end),
                   location: (if $location == "" then null else $location end),
                   region: (if $region == "" then null else $region end) },
            io_mb_s: { run1: $io1, run2: $io2, run3: $io3, average: $ioavg },
            speedtest: $speedtest,
            runtime_sec: $elapsed
        }' >"$out"
    rm -f "$tmp"
}

# --- ambil JSON yang sudah dicetak YABS dari -j -----------------------------
# YABS menulis JSON sebagai satu baris terakhir yang diawali {"version"
# Baris itu diambil dari teks mentah (tanpa sanitize) supaya karakter kutip
# di dalam nilai tidak ikut berubah.
hex_ambil_json_yabs() {
    local in="$1"
    grep -o '{"version".*}' "$in" | tail -1
}