---
title: Contoh VPS NVMe 2
provider: Contoh Cloud (PT Contoh Nusantara)
location: Jakarta, Indonesia
price_monthly: 125000
currency: IDR
cpu_cores: 2
ram_gb: 4
storage_gb: 60
storage_type: NVMe
bandwidth_tb: 3
virtualization: KVM
status: Available
last_updated: 2025-06-01
tags:
  - KVM
  - Indonesia
  - 4GB RAM
affiliate_link: "https://contoh.id/buy?ref=1"
raw_yabs_output: |
  # ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #
  #              Yet-Another-Bench-Script              #
  #                     v2025-04-20                    #
  # https://github.com/masonr/yet-another-bench-script #
  # ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## ## #

  Basic System Information:
  ---------------------------------
  Uptime     : 2 days, 3 hours, 4 minutes
  Processor  : AMD EPYC 9354 32-Core Processor
  CPU cores  : 2 @ 3792 MHz
  AES-NI     : ✔ Enabled
  VM-x/AMD-V : ✔ Enabled
  RAM        : 3.85 GiB
  Swap       : 0.0 KiB
  Disk       : 59.8 GiB
  Distro     : Ubuntu 24.04.2 LTS
  Kernel     : 6.8.0-45-generic
  VM Type    : KVM
  IPv4/IPv6  : ✔ Online / ✔ Online

  IPv4 Network Information:
  ---------------------------------
  ISP        : PT Contoh Nusantara
  ASN        : AS141111 PT Contoh
  Host       : PT Contoh Nusantara
  Location   : Jakarta, Jakarta (JK)
  Country    : Indonesia

  fio Disk Speed Tests (Mixed R/W 50/50) (Partition /dev/vda1):
  ---------------------------------
  Block Size | 4k            (IOPS) | 64k           (IOPS)
    ------   | ---            ----  | ----           ----
  Read       | 512.30 MB/s   (134k)  | 1.85 GB/s     (29.6k)
  Write      | 498.11 MB/s   (130k)  | 1.79 GB/s     (28.7k)
  Total      | 1.00 GB/s     (265k)  | 3.65 GB/s     (58.4k)
             |                      |
  Block Size | 512k          (IOPS) | 1m            (IOPS)
    ------   | ---            ----  | ----           ----
  Read       | 1.21 GB/s     (2.4k)  | 988.20 MB/s    (986)
  Write      | 1.18 GB/s     (2.3k)  | 1.02 GB/s     (1020)
  Total      | 2.39 GB/s     (4.7k)  | 2.01 GB/s     (2.0k)

  iperf3 Network Speed Tests (IPv4):
  ---------------------------------
  Provider        | Location (Link)           | Send Speed      | Recv Speed      | Ping
  -----           | -----                     | ----            | ----            | ----
  KonomanEJPN     | Tokyo, JP (10G)           | 1.20 Gbits/sec  | 980.10 Mbits/sec| 4.20 ms
  iPerf           | Los Angeles, CA, US (10G) | 610 Mbits/sec   | 455.20 Mbits/sec| 158.9 ms
  iPerf           | Singapore, SG (10G)       | 1.05 Gbits/sec  | busy            | 22.5 ms

  Geekbench 6 Benchmark Test:
  ---------------------------------
  Test           | Value
  Single Core    | 1560
  Multi Core     | 3980
  Full Test      | https://browser.geekbench.com/v6/cpu/9876543

  YABS completed in 8 min 41 sec
raw_benchsh_output: |
  -------------------- A Bench.sh Script By Teddysun -------------------
   Version            : v2025-05-08
   Usage              : wget -qO- bench.sh | bash
  ----------------------------------------------------------------------
   CPU Model          : AMD EPYC 9354 32-Core Processor
   CPU Cores          : 2 @ 3792 MHz
   CPU Cache          : 1024 KB
   AES-NI             : ✓ Enabled
   VM-x/AMD-V         : ✓ Enabled
   Total Disk         : 59.8 GB (9.1 GB Used)
   Total Mem          : 3.8 GB (1.1 GB Used)
   System uptime      : 2 days, 3 hour 4 min
   Load average       : 0.11, 0.09, 0.05
   OS                 : Ubuntu 24.04.2 LTS
   Arch               : x86_64 (64 Bit)
   Kernel             : 6.8.0-45-generic
   TCP CC             : bbr
   Virtualization     : KVM
   IPv4/IPv6          : ✓ Online / ✓ Online
   Organization       : AS141111 PT Contoh
   Location           : Jakarta / ID
   Region             : Jakarta
  ----------------------------------------------------------------------
   I/O Speed(1st run) : 3.1 GB/s
   I/O Speed(2nd run) : 2.9 GB/s
   I/O Speed(3rd run) : 3.0 GB/s
   I/O Speed(average) : 3018.4 MB/s
  ----------------------------------------------------------------------
   Node Name        Upload Speed      Download Speed      Latency
   Speedtest.net    612.44 Mbps       948.21 Mbps         0.48 ms
   Singapore, SG    405.10 Mbps       1120.55 Mbps        12.30 ms
   Tokyo, JP        588.72 Mbps       902.31 Mbps         21.07 ms
  ----------------------------------------------------------------------
   Finished in        : 4 min 12 sec
   Timestamp          : 2025-06-01 09:12:33 UTC
  ----------------------------------------------------------------------
---