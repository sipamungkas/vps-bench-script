#!/usr/bin/env bash
# astro_data.sh - mengubah hasil benchmark menjadi sumber data JSON untuk
# project Astro.
#
# sourced oleh tools/vps-bench.
#
# Prinsip: output mentah TIDAK disimpan di dalam JSON. File raw tetap ada di
# src/data/raw/<slug>/ dan dibaca saat build. Alasannya compare.astro
# menyertakan seluruh data VPS ke dalam halaman; kalau teks mentah ikut
# masuk, payload-nya jadi ratusan KB per VPS.
#
# Layout berkas:
#   src/data/vps/<slug>.json      metadata + hasil benchmark (sumber data situs)
#   src/data/raw/<slug>/yabs.txt  output mentah YABS
#   src/data/raw/<slug>/benchsh.txt output mentah bench.sh

hex_slug() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/-\{1,\}$//' -e 's/-\{2,\}/-/g'
}

# Pisahkan nama provider jadi nama pendek + badan usaha, supaya filter
# kategori tidak ikut berubah kalau nama badan usaha ikut berubah.
# "Nevacloud (PT Deneva)" -> "Nevacloud|PT Deneva"
hex_pisah_provider() {
    local n="$1" nama badan
    if [[ "$n" == *'('*')'* ]]; then
        nama="${n%% (*}"
        badan="${n#*(}"
        printf '%s|%s' "$nama" "${badan%)}"
    else
        printf '%s|' "$n"
    fi
}

# --- baca frontmatter Markdown lama -----------------------------------------
# Format .md lama sengaja sempit: skalaris polos, satu daftar (tags), dan dua
# blok skalar (raw_yabs_output / raw_benchsh_output). Cukup ditangani awk,
# jadi tidak perlu pustaka YAML.
#
# Keluaran:
#   <prefix>.meta.json   metadata
#   <prefix>.yabs.txt    blok raw YABS
#   <prefix>.benchsh.txt blok raw bench.sh
# hex_md_lama <file.md> <prefix>
hex_md_lama() {
    local md="$1" pfx="$2"
    [[ -f "$md" ]] || { printf 'Error: %s tidak ditemukan\n' "$md" >&2; return 1; }

    # blok skalar yang dibaca, sisanya diabaikan
    : > "${pfx}.yabs.txt"
    : > "${pfx}.benchsh.txt"

    awk -v yabs_out="${pfx}.yabs.txt" \
        -v bench_out="${pfx}.benchsh.txt" '
    BEGIN { phase = 0; target = ""; listkey = "" }
    NR == 1 && $0 ~ /^---[[:space:]]*$/ { phase = 1; next }
    phase == 1 && $0 ~ /^---[[:space:]]*$/ { phase = 2; exit }

    phase == 1 {
        # "key: |" diikuti isi ter-indent
        if ($0 ~ /^[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*\|[[:space:]]*$/) {
            curkey = substr($0, 1, index($0, ":") - 1)
            if (curkey == "raw_yabs_output")        target = yabs_out
            else if (curkey == "raw_benchsh_output") target = bench_out
            else                                    target = ""
            next
        }
        if (target != "") {
            line = $0
            sub(/^  /, "", line)      # buang indent blok skalar
            print line >> target
            next
        }
        # daftar yaml: "key:" lalu "  - item"
        if ($0 ~ /^[A-Za-z_][A-Za-z0-9_]*:[[:space:]]*$/) {
            listkey = $0
            sub(/:[[:space:]]*$/, "", listkey)
            next
        }
        if (listkey != "" && $0 ~ /^[[:space:]]+-[[:space:]]+/) {
            v = $0
            sub(/^[[:space:]]*-[[:space:]]+/, "", v)
            gsub(/^"|"$/, "", v)
            printf "%s\tITEM\t%s\n", listkey, v
            next
        }
        # skalaris polos "key: value"
        if ($0 ~ /^[A-Za-z_]/ && index($0, ":") > 0) {
            key = substr($0, 1, index($0, ":") - 1)
            v = substr($0, index($0, ":") + 1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
            gsub(/^"|"$/, "", v)
            if (key ~ /^raw_/) next   # blok mentah, bukan metadata
            printf "%s\tVAL\t%s\n", key, v
            next
        }
    }' "$md" > "${pfx}.kv"

    jq -Rn '
        reduce (inputs | split("\t")) as $i
          ({};
            if    $i[1] == "VAL"  then .[$i[0]] =
                   ($i[2] | if test("^-?[0-9]+(\\.[0-9]+)?$") then tonumber else . end)
            elif $i[1] == "ITEM" then .[$i[0]] = ((.[$i[0]] // []) + [$i[2]])
            else . end)
    ' < "${pfx}.kv" > "${pfx}.meta.json"

    rm -f "${pfx}.kv"
    [[ -s "${pfx}.meta.json" ]]
}

# --- program jq penyusun berkas VPS -----------------------------------------
# Semua nilai yang sering dipakai UI dihitung di sini (summary), supaya
# halaman tidak perlu menghitung ulang tiap kali render.
# Summary juga sengaja dibuat datar supaya mudah dibandingkan antar VPS.
HEX_VPS_JQ='
# KBps -> MB/s, dibulatkan 1 desimal supaya enak dibaca di kartu statistik
def mbps: if . == null then null else (((. / 1024) * 10 | round) / 10) end;

# Kecepatan jaringan -> Mbit/s, supaya "1.20 Gbits/sec" dan "610 Mbits/sec"
# bisa dibandingkan. Tanpa ini, 1.20 dianggap lebih kecil dari 610 karena
# angkanya dibandingkan apa adanya.
def mbit:
    (split(" ") | .[0] | tonumber?) as $n
    | if    $n == null  then 0
      elif test("Gbit") then $n * 1000
      elif test("Kbit") then $n * 0.001
      else $n end;

($meta[0]  // {}) as $m
| ($yabs[0] // {}) as $Y
| ($bench[0]// {}) as $B
| ($provider | split("|")) as $pp
| (($Y.geekbench // []) | map(select(.single != null)) | last) as $gb
| (($Y.fio // []) | map(.iops_rw)  | map(select(. != null)) | max) as $maxiops
| (($Y.fio // []) | map(.speed_r) | map(select(. != null)) | max) as $maxr
| (($Y.fio // []) | map(.speed_w) | map(select(. != null)) | max) as $maxw
| (($Y.iperf // [])
     | map(select(.mode == "IPv4" and .send != "busy"))
     | map(select((.send // "") | test("^[0-9]")))
     | map(. + {n: (.send | mbit)})
   ) as $iperf4
| (if ($iperf4 | length) > 0
   then ($iperf4 | max_by(.n) | .send) else null end) as $bestsend
| (($B.speedtest // [])
     | map(select((.download // "") | test("^[0-9]")))
     | map(. + {n: (.download | mbit)})
   ) as $dlrows
| (if ($dlrows | length) > 0
   then ($dlrows | max_by(.n) | .download) else null end) as $bestdl
| {
    slug: $slug,
    title:          ($m.title          // $slug),
    provider:       (if ($pp[0] // "") != "" then $pp[0] else ($m.provider // "Unknown") end),
    provider_legal: (if ($pp[1] // "") != "" then $pp[1] else ($m.provider_legal // null) end),
    location:       ($m.location       // null),
    price_monthly:  ($m.price_monthly  // null),
    currency:       ($m.currency       // null),
    cpu_cores:      ($m.cpu_cores      // null),
    ram_gb:         ($m.ram_gb         // null),
    storage_gb:     ($m.storage_gb     // null),
    storage_type:   ($m.storage_type   // null),
    bandwidth_tb:   ($m.bandwidth_tb   // null),
    virtualization: ($m.virtualization // null),
    status:         ($m.status         // "Unknown"),
    last_updated:   ($m.last_updated   // null),
    affiliate_link: ($m.affiliate_link // null),
    tags:           ($m.tags           // []),
    summary: {
      geekbench_single:        ($gb.single // null),
      geekbench_multi:         ($gb.multi  // null),
      max_iops:                ($maxiops   // null),
      max_read_mb_s:           ($maxr | mbps),
      max_write_mb_s:          ($maxw | mbps),
      # dibulatkan 1 desimal: parser menulis 2 desimal, jadi JSON akan menyimpan
      # literal seperti 3018.40 yang tampil excessive di kartu statistik
      dd_avg_mb_s:             (if ($B.io_mb_s.average // null) == null then null
                                else ((($B.io_mb_s.average * 10) | round) / 10) end),
      best_iperf_send:         ($bestsend  // null),
      speedtest_best_download: ($bestdl    // null)
    },
    benchmarks: {
      yabs:    (if ($Y | length) > 0 then ($Y + {raw_file: "yabs.txt"})    else null end),
      benchsh: (if ($B | length) > 0 then ($B + {raw_file: "benchsh.txt"}) else null end)
    }
  }
'

# --- tulis / gabung berkas VPS ----------------------------------------------
# Metadata lama dipertahankan; hanya blok benchmarks + summary yang diperbarui.
# Jadi benchmark baru tidak menghapus harga/kategori yang diisi manual.
# hex_tulis_vps <slug> <meta_json> <json_yabs> <json_bench>
hex_tulis_vps() {
    local slug="$1" meta="$2" jy="$3" jb="$4" out tmp provider

    mkdir -p "$VPS_DATA_DIR"
    out="$VPS_DATA_DIR/$slug.json"

    # Metadata lama jadi dasar, supaya update benchmark tidak menimpa info manual.
    # Cukup buang bagian yang memang dihitung ulang - daftar field manual
    # yang dicopy satu per satu prone kelewatan (sudah pernah membuat `provider`
    # hilang saat import ulang).
    if [[ -s "$out" ]]; then
        jq 'del(.slug, .summary, .benchmarks)' "$out" > "${meta}.base"
        jq -s '.[0] * .[1]' "${meta}.base" "$meta" > "${meta}.merged"
        meta="${meta}.merged"
    fi

    # Susun "nama_pendek|badan_usaha" dari metadata yang sudah digabung
    local nama badan
    nama="$(jq -r '.provider // ""' "$meta" 2>/dev/null)"
    badan="$(jq -r '.provider_legal // ""' "$meta" 2>/dev/null)"
    if [[ "$nama" == *"("*")"* ]]; then
        provider="$(hex_pisah_provider "$nama")"
    elif [[ -n "$nama" && -n "$badan" ]]; then
        provider="$nama|$badan"
    else
        provider="$nama|"
    fi
    [[ -z "${provider%%|*}" ]] && provider="Unknown|"

    tmp="$(mktemp "${TMPDIR:-/tmp}/vpsjson.XXXXXX")"
    jq -n \
        --arg slug "$slug" \
        --arg provider "$provider" \
        --slurpfile meta "$meta" \
        --slurpfile yabs "$jy" \
        --slurpfile bench "$jb" \
        "$HEX_VPS_JQ" > "$tmp"

    mv "$tmp" "$out"
    rm -f "${meta}.base" "${meta}.merged"
    printf '%s' "$out"
}