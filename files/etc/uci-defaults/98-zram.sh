#!/bin/sh
# 设置 zram 默认压缩算法为 lzo-rle

uci -q set system.@system[0].zram_comp_algo='lzo-rle'
uci -q set system.@system[0].zram_priority='100'
uci commit system

exit 0
