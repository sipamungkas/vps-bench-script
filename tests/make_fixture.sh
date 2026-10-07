#!/usr/bin/env bash
# make_fixture.sh - hasilkan output benchmark tiruan yang sedekat mungkin dengan
# output asli bench.sh dan YABS.sh, termasuk kode warna ANSI dan sisa escape
# sequence dari `clear` yang tetap muncul saat stdout di-pipe.
#
# Tujuannya memberi bahan uji parser tanpa harus menyewa VPS sungguhan.
# Fixture ini TIDAK meantik sebagai data benchmark nyata.

set -u
OUT="$(cd "$(dirname "$0")" && pwd)"

# --- fungsi warna yang disalin apa adanya dari bench.sh ---------------------
_red()    { printf '\033[0;31;31m%b\033[0m' "${1}"; }
_green()  { printf '\033[0;31;32m%b\033[0m' "${1}"; }
_yellow() { printf '\033[0;31;33m%b\033[0m' "${1}"; }
_blue()   { printf '\033[0;31;34m%b\033[0m' "${1}"; }

gen_bench() {
    # yang dicetak `clear` saat stdout bukan tty
    printf '\033[3J\033[H\033[2J'

    echo "-------------------- A Bench.sh Script By Teddysun -------------------"
    echo " Version            : $(_green v2026-01-31)"
    echo " Usage              : $(_red "wget -qO- bench.sh | bash")"
    printf "%-70s\n" "-" | sed 's/\s/-/g'
    echo " CPU Model          : $(_blue "Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz")"
    echo " CPU Cores          : $(_blue "2 @ 2400 MHz")"
    echo " CPU Cache          : $(_blue "8192 KB")"
    echo " AES-NI             : $(_green "\xe2\x9c\x93 Enabled")"
    echo " VM-x/AMD-V         : $(_green "\xe2\x9c\x93 Enabled")"
    echo " Total Disk         : $(_yellow "80.0 GB") $(_blue "(21.4 GB Used)")"
    echo " Total RAM          : $(_yellow "3.9 GB") $(_blue "(1.2 GB Used)")"
    echo " Total Swap         : $(_blue "0 B (0 B Used)")"
    echo " System Uptime      : $(_blue "14 days, 6 hours, 21 minutes")"
    echo " Load Average       : $(_blue "0.12, 0.09, 0.07")"
    echo " OS                 : $(_blue "Ubuntu 22.04.4 LTS")"
    echo " Arch               : $(_blue "x86_64 (64 Bit)")"
    echo " Kernel             : $(_blue "5.15.0-119-generic")"
    echo " TCP Congestion Ctrl: $(_yellow "bbr")"
    echo " Virtualization     : $(_blue "kvm")"
    echo " IPv4/IPv6          : $(_green "\xe2\x9c\x93 Online") / $(_green "\xe2\x9c\x93 Online")"
    echo " Organization       : $(_blue "AS64496 Example Hosting")"
    echo " Location           : $(_blue "Amsterdam / NL")"
    echo " Region             : $(_yellow "North Holland")"
    printf "%-70s\n" "-" | sed 's/\s/-/g'
    echo " I/O Speed(1st run) : $(_yellow "612.44") MB/s"
    echo " I/O Speed(2nd run) : $(_yellow "588.10") MB/s"
    echo " I/O Speed(3rd run) : $(_yellow "601.77") MB/s"
    echo " I/O Speed(average) : $(_yellow "600.77 MB/s")"
    printf "%-70s\n" "-" | sed 's/\s/-/g'

    # tabel speedtest: printf "%-18s%-18s%-20s%-12s" node up down latency
    # node | upload | download | latency
    local rows
    printf "\033[0;33m%-18s\033[0;32m%-18s\033[0;31m%-20s\033[0;36m%-12s\033[0m\n" \
        " Speedtest.net" "42.15 Mbit/s" "168.72 Mbit/s" "8.44 ms"
    for r in \
        "Los Angeles, US:51.02 Mbit/s:204.31 Mbit/s:152.88 ms" \
        "Dallas, US:48.77 Mbit/s:196.05 Mbit/s:44.19 ms" \
        "Montreal, CA:52.90 Mbit/s:212.44 Mbit/s:151.02 ms" \
        "Paris, FR:47.11 Mbit/s:189.63 Mbit/s:12.77 ms" \
        "Amsterdam, NL:50.05 Mbit/s:201.88 Mbit/s:9.31 ms" \
        "Suzhou, CN:18.22 Mbit/s:74.55 Mbit/s:182.40 ms" \
        "Hong Kong, CN:12.03 Mbit/s:48.91 Mbit/s:186.55 ms" \
        "Singapore, SG:16.88 Mbit/s:67.24 Mbit/s:170.02 ms" \
        "Tokyo, JP:22.41 Mbit/s:89.70 Mbit/s:164.18 ms"
    do
        IFS=':' read -r node up down lat <<<"$r"
        printf "\033[0;33m%-18s\033[0;32m%-18s\033[0;31m%-20s\033[0;36m%-12s\033[0m\n" \
            " $node" "$up" "$down" "$lat"
    done
    # baris gagal - harus diabaikan parser
    printf "\033[0;33m%-18s\033[0;31m%-18s\033[0m\n" " Sydney, AU" "Test failed"

    printf "%-70s\n" "-" | sed 's/\s/-/g'
    echo " Finished in        : 6 min 47 sec"
    echo " Timestamp          : 2026-10-07 03:14:52"
    echo "----------------------------------------------------------------------"
}

gen_yabs() {
    echo -e '# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #'
    echo -e '#              Yet-Another-Bench-Script              #'
    echo -e '#                     v2026-09-20                    #'
    echo -e '# https://github.com/masonr/yet-another-bench-script #'
    echo -e '# ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #'
    echo -e
    # Tanggal dikunci, bukan `date`. Kalau memakai date, setiap `pnpm test`
    # menulis ulang fixture dan working tree jadi tidak bersih.
    echo "Tue Sep 22 03:14:05 UTC 2026"
    echo -e
    echo -e "Basic System Information:"
    echo -e "---------------------------------"
    echo -e "Uptime     : 14 days, 6 hours, 21 minutes"
    echo -e "Processor  : Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz"
    echo -e "CPU cores  : 2 @ 2400 MHz"
    echo -e "AES-NI     : ✓ Enabled"
    echo -e "VM-x/AMD-V : ✓ Enabled"
    echo -e "RAM        : 3.9 GiB"
    echo -e "Swap       : 0.00 B"
    echo -e "Disk       : 80.00 GiB"
    echo -e "Distro     : Ubuntu 22.04.4 LTS"
    echo -e "Kernel     : 5.15.0-119-generic"
    echo -e "VM Type    : KVM"
    echo -e "IPv4/IPv6  : ✓ Online / ✓ Online"
    echo -e
    echo -e " IPv4: AS64496 Example Hosting @ Amsterdam, North Holland, NL"
    echo -e
    echo -e "fio Disk Speed Tests (Mixed R/W 50/50) (Partition /dev/vda1):"
    echo -e "---------------------------------"
    printf "%-10s | %-11s %8s | %-11s %8s\n" "Block Size" "4KiB" "(IOPS)" "1MiB" "(IOPS)"
    printf "%-10s | %-11s %8s | %-11s %8s\n" "  ------" "---" "---- " "----" "---- "
    printf "%-10s | %-11s %8s | %-11s %8s\n" "Read" "88.12 MB/s" "(23013 iops)" "412.55 MB/s" "(1025 iops)"
    printf "%-10s | %-11s %8s | %-11s %8s\n" "Write" "71.44 MB/s" "(18203 iops)" "388.09 MB/s" "(981 iops)"
    printf "%-10s | %-11s %8s | %-11s %8s\n" "Mixed" "79.01 MB/s" "(20620 iops)" "400.77 MB/s" "(1003 iops)"
    echo -e
    echo -e "iperf3 Network Speed Tests (IPv4):"
    echo -e "---------------------------------"
    printf "%-15s | %-25s | %-15s | %-15s | %-15s\n" "Provider" "Location (Link)" "Send Speed" "Recv Speed" "Ping"
    printf "%-15s | %-25s | %-15s | %-15s | %-15s\n" "-----" "-----" "----" "----" "----"
    printf "%-15s | %-25s | %-15s | %-15s | %-15s\n" "iPerf" "Warsaw, Poland (10G)" "412.55 Mbit/s" "180.22 Mbit/s" "187.9 ms"
    printf "%-15s | %-25s | %-15s | %-15s | %-15s\n" "iPerf" "Amsterdam, NL (10G)" "455.10 Mbit/s" "201.77 Mbit/s" "12.4 ms"
    printf "%-15s | %-25s | %-15s | %-15s | %-15s\n" "iPerf" "London, UK (1G)" "0.00 Mbit/s" "0.00 Mbit/s" "21.0 ms"
    echo -e
    echo -e "Geekbench 6 Benchmark Test:"
    echo -e "---------------------------------"
    printf "%-15s | %-30s\n" "Test" "Value"
    printf "%-15s | %-30s\n" "" ""
    printf "%-15s | %-30s\n" "Single Core" "812"
    printf "%-15s | %-30s\n" "Multi Core" "1447"
    printf "%-15s | %-30s\n" "Full Test" "https://browser.geekbench.com/v6/cpu/1234567"
    echo -e
    echo "YABS completed in 9 min 12 sec"
}

# JSON native YABS, disusun mengikuti skema JSON_RESULT di yabs.sh
gen_yabs_json() {
    cat <<'JSON'
{"version":"v2026-09-20","time":"20261007-031452","os":{"arch":"x86_64","distro":"Ubuntu 22.04.4 LTS","kernel":"5.15.0-119-generic","uptime":1234567,"vm":"KVM"},"net":{"ipv4":true,"ipv6":true},"cpu":{"model":"Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz","cores":2,"freq":"2400","aes":true,"virt":true},"mem":{"ram":4194304,"ram_units":"KiB","swap":0,"swap_units":"KiB","disk":83886080,"disk_units":"KB"},"ip_info":{"protocol":"IPv4","isp":"Example Hosting","asn":"AS64496","org":"Example Hosting BV","city":"Amsterdam","region":"North Holland","region_code":"NH","country":"NL"},"partition":"/dev/vda1","fio":[{"bs":"4KiB","speed_r":90235,"iops_r":23013,"speed_w":73155,"iops_w":18203,"speed_rw":80906,"iops_rw":20620,"speed_units":"KBps"},{"bs":"1MiB","speed_r":422451,"iops_r":1025,"speed_w":397404,"iops_w":981,"speed_rw":410388,"iops_rw":1003,"speed_units":"KBps"}],"iperf":[{"mode":"IPv4","provider":"iPerf","loc":"Warsaw, Poland (10G)","send":"412.55 Mbit/s","recv":"180.22 Mbit/s","latency":"187.9 ms"},{"mode":"IPv4","provider":"iPerf","loc":"Amsterdam, NL (10G)","send":"455.10 Mbit/s","recv":"201.77 Mbit/s","latency":"12.4 ms"},{"mode":"IPv4","provider":"iPerf","loc":"London, UK (1G)","send":"busy","recv":"busy","latency":"21.0 ms"}],"geekbench":[{"version":6,"single":812,"multi":1447,"url":"https://browser.geekbench.com/v6/cpu/1234567"}],"runtime":{"start":1759896892,"end":1759897444,"elapsed":552}}
JSON
}

case "${1:-all}" in
    bench)     gen_bench >"$OUT/fixture-bench.txt" ;;
    yabs)      gen_yabs  >"$OUT/fixture-yabs.txt" ;;
    yabs-json) { gen_yabs; gen_yabs_json; } >"$OUT/fixture-yabs-json.txt" ;;
    all)       gen_bench >"$OUT/fixture-bench.txt"
               gen_yabs  >"$OUT/fixture-yabs.txt"
               { gen_yabs; gen_yabs_json; } >"$OUT/fixture-yabs-json.txt" ;;
esac
printf 'fixture dibuat di %s\n' "$OUT"