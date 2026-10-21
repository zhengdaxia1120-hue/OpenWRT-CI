#!/bin/sh
# 将 zram 压缩算法默认设为 lzo-rle

uci -q batch <<EOF
set system.zram=zram
set system.zram.comp_algorithm='lzo-rle'
commit system
EOF

exit 0
