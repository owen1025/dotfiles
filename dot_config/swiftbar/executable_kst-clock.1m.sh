#!/bin/bash

# <xbar.title>KST Clock</xbar.title>
# <xbar.desc>Shows Korea Standard Time in menu bar</xbar.desc>
# <xbar.version>v1.0</xbar.version>

KST_AMPM=$(TZ="Asia/Seoul" date +"%p" | sed 's/AM/오전/;s/PM/오후/')
KST_TIME=$(TZ="Asia/Seoul" date +"%I:%M")
KST_FULL=$(TZ="Asia/Seoul" date +"%Y-%m-%d %a")

echo "🇰🇷 ${KST_AMPM} ${KST_TIME}"
echo "---"
echo "🇰🇷 KST: ${KST_FULL} ${KST_AMPM} ${KST_TIME} | font=monospace"
