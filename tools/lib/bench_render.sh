#!/usr/bin/env bash
# bench_render.sh - ubah JSON hasil benchmark menjadi tabel Markdown.
#
# sourced oleh bin/bench-export. Hanya memakai jq, tanpa template engine.
#
# Renderer ini harus menangani DUA bentuk JSON YABS:
#   1. JSON native dari flag -j  : field numerik + satuan terpisah
#                               (mis. .mem.ram = 4194304, .mem.ram_units = "KiB")
#   2. JSON dari parser teks     : field berupa string siap tampil
#                               (mis. .mem.ram = "3.9 GiB")
# Karena itu setiap sel numerik selalu digabung dengan satiannya bila ada.

jq_defs='
def cell:  if . == null then "-" else tostring end;
def cellx: if . == null or . == "" then "-" else tostring end;
def num:   if . == null then "-" else tostring end;

# JSON native YABS menyimpan byte dalam satuan baku, jadi readability jelek
# (mis. 4194304 KiB). Ubah ke satuan yang enak dibaca.
def human_kib:
    if . == null then "-"
    else . as $v
      | if    $v >= 1048576 then "\(($v / 1048576 * 100 | round) / 100) GiB"
        elif $v >= 1024    then "\(($v / 1024    * 100 | round) / 100) MiB"
        else "\($v) KiB" end
    end;

# RAM/Swap/Disk: kalau satuan sudah terpisah, konversi ke satuan ramah baca.
# Kalau parser teks sudah menghasilkan string ("3.9 GiB"), pakai apa adanya.
#
# CATATAN: YABS menulis disk_units "KB", padahal nilainya diambil dari field
# `df` yaitu blok 1K - jadi basisnya 1024 (KiB), bukan 1000. Karena itu "KB"
# diperlakukan sama dengan KiB di sini. Verify ulang kalau upstream YABS
# suatu saat memperbaiki label tersebut.
def memcell(field; unitfield):
    .[field] as $v
    | .[unitfield]? as $u
    | if    $v == null then "-"
      elif $u == null then ($v | tostring)
      elif $u == "KiB" or $u == "MiB" or $u == "KB" or $u == "MB" then ($v | human_kib)
      elif $u == "TiB" or $u == "TB" then ($v | human_kib)
      else "\($v) \($u)" end;

# Uptime bisa string ("14 days, 6 hours") atau angka detik (JSON native).
def dur:
    if . == null then "-"
    elif (type == "number") then . as $s
      | if    $s >= 86400 then "\(($s / 86400 | floor))d \((($s / 3600 | floor) % 24))h \((($s / 60 | floor) % 60))m"
        elif $s >= 3600  then "\(($s / 3600 | floor))h \((($s / 60 | floor) % 60))m"
        elif $s >= 60    then "\(($s / 60 | floor))m \(($s % 60))s"
        else "\($s)s" end
    else tostring
    end;

def uptimecell: (.uptime // .os.uptime? // null) | dur;

# Runtime bisa .runtime_sec (parser teks) atau .runtime.elapsed (native).
def runtimecell:
    (.runtime_sec // .runtime.elapsed? // null) as $t
    | if $t == null then "" else "Runtime: \($t | dur)\n" end;

def yesno:  if . == null then "-" else (if . then "yes" else "no" end) end;
def online: if . == null then "-" else (if . then "online" else "offline" end) end;

# YABS menulis waktu sebagai %Y%m%d-%H%M%S. Rapikan jadi format biasa.
def stamp:
    if . == null then "n/a"
    elif (type == "string" and test("^[0-9]{8}-[0-9]{6}$")) then
        (.[0:4] + "-" + .[4:6] + "-" + .[6:8] + " " + .[9:11] + ":" + .[11:13] + ":" + .[13:15])
    else tostring end;
'

# --- YABS -> Markdown --------------------------------------------------------
# hex_render_yabs <json> <keluaran_md>
hex_render_yabs() {
    local json="$1" out="$2"

    jq -r "$jq_defs"'
      . as $r |

      "# Benchmark Report - YABS\n" +
      "Generated: " + (now | gmtime | strftime("%Y-%m-%d %H:%M:%S UTC")) + "\n" +
      "Script version: " + ($r.version // "n/a") + "\n" +
      "Parsed at: " + ($r.time | stamp) + "\n" +
      ($r | runtimecell) +

      "\n## System\n" +
      "| Field | Value |\n|---|---|\n" +
      "| Distro | " + ($r.os.distro | cellx) + " |\n" +
      "| Kernel | " + ($r.os.kernel | cellx) + " |\n" +
      "| Arch | " + ($r.os.arch | cellx) + " |\n" +
      "| VM Type | " + (($r.vm // $r.os.vm?) | cellx) + " |\n" +
      "| Uptime | " + ($r | uptimecell) + " |\n" +
      "| CPU | " + ($r.cpu.model | cellx) + " |\n" +
      "| CPU Cores | " + ($r.cpu.cores | num) + " |\n" +
      "| CPU Freq | " + ($r.cpu.freq | cellx) + " |\n" +
      "| AES-NI | " + ($r.cpu.aes | yesno) + " |\n" +
      "| RAM | " + ($r.mem | memcell("ram"; "ram_units")) + " |\n" +
      "| Swap | " + ($r.mem | memcell("swap"; "swap_units")) + " |\n" +
      "| Disk | " + ($r.mem | memcell("disk"; "disk_units")) + " |\n" +
      "| IPv4 | " + ($r.net.ipv4 | online) + " |\n" +
      "| IPv6 | " + ($r.net.ipv6 | online) + " |\n" +

      (if $r.ip_info? != null then
        "\n## Network Info\n" +
        "| Field | Value |\n|---|---|\n" +
        "| ISP | " + ($r.ip_info.isp | cellx) + " |\n" +
        "| ASN | " + ($r.ip_info.asn | cellx) + " |\n" +
        "| Org | " + ($r.ip_info.org | cellx) + " |\n" +
        "| City | " + ($r.ip_info.city | cellx) + " |\n" +
        "| Region | " + ($r.ip_info.region | cellx) + " |\n" +
        "| Country | " + ($r.ip_info.country | cellx) + " |\n"
      else "" end) +

      (if ($r.fio? // [] | length) > 0 then
        "\n## Disk (fio, mixed R/W 50/50)\n" +
        (if $r.partition? != null then "Partition: `" + $r.partition + "`\n" else "" end) +
        "| Block Size | Read | Read IOPS | Write | Write IOPS |\n|---|---|---|---|---|\n" +
        ($r.fio | map(
          "| " + (.bs | cellx) + " | " + (.speed_r | num) + " | " + (.iops_r | num) + " | " +
          (.speed_w | num) + " | " + (.iops_w | num) + " |"
        ) | join("\n")) + "\n"
      else "" end) +

      (if ($r.iperf? // [] | length) > 0 then
        "\n## Network (iperf3)\n" +
        "| Provider | Location | Send | Recv | Ping |\n|---|---|---|---|---|\n" +
        ($r.iperf | map(
          "| " + (.provider | cellx) + " | " + (.loc | cellx) + " | " + (.send | cellx) + " | " +
          (.recv | cellx) + " | " + (.latency | cellx) + " |"
        ) | join("\n")) + "\n"
      else "" end) +

      (if ($r.geekbench? // [] | length) > 0 then
        "\n## Geekbench\n" +
        "| Version | Single | Multi | Report |\n|---|---|---|---|\n" +
        ($r.geekbench | map(
          "| " + (.version | num) + " | " + (.single | num) + " | " + (.multi | num) + " | " +
          (if .url? then "[link](" + .url + ")" else "-" end) + " |"
        ) | join("\n")) + "\n"
      else "" end)
    ' "$json" >"$out"
}

# --- bench.sh -> Markdown ----------------------------------------------------
hex_render_bench() {
    local json="$1" out="$2"

    jq -r "$jq_defs"'
      . as $r |

      "# Benchmark Report - bench.sh (Teddysun)\n" +
      "Generated: " + (now | gmtime | strftime("%Y-%m-%d %H:%M:%S UTC")) + "\n" +
      "Script version: " + ($r.version // "n/a") + "\n" +
      "Timestamp: " + ($r.time | stamp) + "\n" +
      ($r | runtimecell) +

      "\n## System\n" +
      "| Field | Value |\n|---|---|\n" +
      "| OS | " + ($r.system.os | cellx) + " |\n" +
      "| Arch | " + ($r.system.arch | cellx) + " |\n" +
      "| Kernel | " + ($r.system.kernel | cellx) + " |\n" +
      "| Virtualization | " + ($r.system.virtualization | cellx) + " |\n" +
      "| TCP Congestion | " + ($r.system.tcp_congestion | cellx) + " |\n" +
      "| Uptime | " + ($r.system.uptime | cellx) + " |\n" +
      "| Load Average | " + ($r.system.load_average | cellx) + " |\n" +
      "| CPU | " + ($r.cpu.model | cellx) + " |\n" +
      "| CPU Cores | " + ($r.cpu.cores_raw | cellx) + " |\n" +
      "| CPU Cache | " + ($r.cpu.cache | cellx) + " |\n" +
      "| AES-NI | " + ($r.cpu.aes | yesno) + " |\n" +
      "| VM-x/AMD-V | " + ($r.cpu.virt_flag | yesno) + " |\n" +
      "| RAM | " + ($r.mem.ram | cellx) + " |\n" +
      "| Swap | " + ($r.mem.swap | cellx) + " |\n" +
      "| Disk | " + ($r.mem.disk | cellx) + " |\n" +
      "| IPv4 | " + ($r.net.ipv4 | online) + " |\n" +
      "| IPv6 | " + ($r.net.ipv6 | online) + " |\n" +

      (if ($r.net.organization? != null or $r.net.location? != null) then
        "\n## Network Info\n" +
        "| Field | Value |\n|---|---|\n" +
        "| Organization | " + ($r.net.organization | cellx) + " |\n" +
        "| Location | " + ($r.net.location | cellx) + " |\n" +
        "| Region | " + ($r.net.region | cellx) + " |\n"
      else "" end) +

      (if $r.io_mb_s.average != null then
        "\n## Disk I/O (dd, 3 runs)\n" +
        "| Run 1 (MB/s) | Run 2 (MB/s) | Run 3 (MB/s) | Average (MB/s) |\n|---|---|---|---|\n" +
        "| " + ($r.io_mb_s.run1 | num) + " | " + ($r.io_mb_s.run2 | num) + " | " +
        ($r.io_mb_s.run3 | num) + " | " + ($r.io_mb_s.average | num) + " |\n"
      else "" end) +

      (if ($r.speedtest? // [] | length) > 0 then
        "\n## Network (speedtest.net)\n" +
        "| Node | Upload | Download | Latency |\n|---|---|---|---|\n" +
        ($r.speedtest | map(
          "| " + (.node | cellx) + " | " + (.upload | cellx) + " | " +
          (.download | cellx) + " | " + (.latency | cellx) + " |"
        ) | join("\n")) + "\n"
      else "" end)
    ' "$json" >"$out"
}

# --- VPS (gabungan) -> Markdown ------------------------------------------------
# Satu laporan yang memuat metadata paket, ringkasan angka, lalu laporan YABS
# dan bench.sh apa adanya di bawahnya. Dipakai oleh vps-bench-standalone supaya
# hasilnya tidak perlu digabung manual.
#
# Benchmarks yang tidak ada (null) dilewati diam-diam - slug yang baru diimpor
# sering hanya punya satu dari keduanya.
#
# hex_render_vps <vps_json> <keluaran_md>
hex_render_vps() {
    local json="$1" out="$2" tmp_a tmp_b

    if ! jq -e . "$json" >/dev/null 2>&1; then
        printf 'Error: %s bukan JSON yang valid\n' "$json" >&2
        return 1
    fi

    tmp_a="$(mktemp "${TMPDIR:-/tmp}/vpsmd.yabs.XXXXXX")" || return 1
    tmp_b="$(mktemp "${TMPDIR:-/tmp}/vpsmd.bench.XXXXXX")" || { rm -f "$tmp_a"; return 1; }

    if jq -e '.benchmarks.yabs != null' "$json" >/dev/null 2>&1; then
        jq '.benchmarks.yabs' "$json" >"$tmp_a"
        hex_render_yabs "$tmp_a" "$tmp_a.md" || { rm -f "$tmp_a" "$tmp_b"; return 1; }
        mv "$tmp_a.md" "$tmp_a"
    fi
    if jq -e '.benchmarks.benchsh != null' "$json" >/dev/null 2>&1; then
        jq '.benchmarks.benchsh' "$json" >"$tmp_b"
        hex_render_bench "$tmp_b" "$tmp_b.md" || { rm -f "$tmp_a" "$tmp_b"; return 1; }
        mv "$tmp_b.md" "$tmp_b"
    fi

    jq -r "$jq_defs"'
      def tags: if ((. // []) | length) > 0 then join(", ") else "-" end;
      def harga:
        if .price_monthly == null then "-"
        else (if .currency == null then (.price_monthly | tostring)
              else ((.price_monthly | tostring) + " " + .currency) end)
        end;
      def bold: if . == null then "-" else "**" + (. | tostring) + "**" end;
      . as $v
      | "# " + (($v.title // $v.slug // "VPS") | tostring) + "\n" +
        "Generated: " + (now | gmtime | strftime("%Y-%m-%d %H:%M:%S UTC")) + "\n" +

        "\n## Paket\n" +
        "| Field | Value |\n|---|---|\n" +
        "| Slug | " + ($v.slug | cellx) + " |\n" +
        "| Provider | " + ($v.provider | cellx) + " |\n" +
        "| Badan usaha | " + ($v.provider_legal | cellx) + " |\n" +
        "| Lokasi | " + ($v.location | cellx) + " |\n" +
        "| Harga bulanan | " + ($v | harga) + " |\n" +
        "| CPU cores | " + ($v.cpu_cores | num) + " |\n" +
        "| RAM (GB) | " + ($v.ram_gb | num) + " |\n" +
        "| Storage (GB) | " + ($v.storage_gb | num) + " |\n" +
        "| Storage type | " + ($v.storage_type | cellx) + " |\n" +
        "| Bandwidth (TB) | " + ($v.bandwidth_tb | num) + " |\n" +
        "| Virtualization | " + ($v.virtualization | cellx) + " |\n" +
        "| Status | " + ($v.status | cellx) + " |\n" +
        "| Affiliate | " + ($v.affiliate_link | cellx) + " |\n" +
        "| Tags | " + ($v.tags | tags) + " |\n" +
        "| Diperbarui | " + ($v.last_updated | cellx) + " |\n" +

        "\n## Ringkasan\n" +
        "| Metrik | Nilai |\n|---|---|\n" +
        "| Geekbench single | " + ($v.summary.geekbench_single | num) + " |\n" +
        "| Geekbench multi | " + ($v.summary.geekbench_multi | num) + " |\n" +
        "| Max IOPS | " + ($v.summary.max_iops | num) + " |\n" +
        "| Max read (MB/s) | " + ($v.summary.max_read_mb_s | num) + " |\n" +
        "| Max write (MB/s) | " + ($v.summary.max_write_mb_s | num) + " |\n" +
        "| dd average (MB/s) | " + ($v.summary.dd_avg_mb_s | num) + " |\n" +
        "| iperf3 send terbaik | " + ($v.summary.best_iperf_send | cellx) + " |\n" +
        "| Speedtest download terbaik | " + ($v.summary.speedtest_best_download | cellx) + " |\n"
    ' "$json" >"$out" || { rm -f "$tmp_a" "$tmp_b"; return 1; }

    # Laporan di bawah dinurunkan satu level heading supaya tidak menabrak
    # "# Judul" di atas. Baris judul dan "Generated:" milik masing-masing
    # laporan dibuang, supaya tidak ada dua timestamp dalam satu file.
    if [[ -s "$tmp_a" ]]; then
        printf '\n## YABS\n\n' >>"$out"
        hex_md_turunkan "$tmp_a" >>"$out"
    fi
    if [[ -s "$tmp_b" ]]; then
        printf '\n## bench.sh\n\n' >>"$out"
        hex_md_turunkan "$tmp_b" >>"$out"
    fi

    rm -f "$tmp_a" "$tmp_b"
}

# hex_md_turunkan: buang judul + baris Generated, naikkan heading satu level.
hex_md_turunkan() {
    sed -e '1d' -e '/^Generated: /d' -e 's/^\(#\{1,\}\)/#\1/' "$1"
}

# Pilih renderer berdasarkan isi JSON.
# JSON native YABS tidak punya field .schema, jadi dideteksi dari strukturnya.
# hex_render_auto <json> <keluaran_md>
hex_render_auto() {
    local json="$1" out="$2" schema
    if ! jq -e . "$json" >/dev/null 2>&1; then
        printf 'Error: %s bukan JSON yang valid\n' "$json" >&2
        return 1
    fi
    schema="$(jq -r '.schema // empty' "$json" 2>/dev/null)"
    if [[ -z "$schema" ]]; then
        if jq -e 'has("os") and has("cpu") and has("mem")' "$json" >/dev/null 2>&1; then
            schema="yabs"
        else
            schema="unknown"
        fi
    fi
    case "$schema" in
        yabs)  hex_render_yabs "$json" "$out" ;;
        bench) hex_render_bench "$json" "$out" ;;
        *)
            printf 'Error: tidak bisa menentukan tipe JSON (schema=%s)\n' "${schema:-kosong}" >&2
            return 1
            ;;
    esac
}