#!/usr/bin/env python3
"""Convert a LineageOS/AOSP apns-conf.xml into the compact payload/apns.tsv.

Usage:
    python make_apn_tsv.py [apns-conf.xml] [apns.tsv]

Source: https://github.com/LineageOS/android_vendor_apn (Apache-2.0),
        or the apns-conf.xml inside the Debian lineageos-apndb package.
"""
import os
import sys
import xml.etree.ElementTree as ET

src = sys.argv[1] if len(sys.argv) > 1 else "apns-conf.xml"
dst = sys.argv[2] if len(sys.argv) > 2 else "apns.tsv"

root = ET.parse(src).getroot()
rows = []


def clean(value):
    return (value or "").replace("\t", " ").replace("\n", " ").replace("\r", " ").strip()


for element in root:
    attrs = element.attrib
    mcc = attrs.get("mcc", "").strip()
    mnc = attrs.get("mnc", "").strip()
    if not mcc or not mnc:
        continue
    rows.append([
        mcc + mnc,
        mcc,
        mnc,
        clean(attrs.get("carrier", "")),
        clean(attrs.get("apn", "")),
        clean(attrs.get("type", "")) or "default",
        clean(attrs.get("protocol", "IP")) or "IP",
        clean(attrs.get("roaming_protocol", "IP")) or "IP",
        clean(attrs.get("mvno_type", "")),
        clean(attrs.get("mvno_match_data", "")),
    ])

rows.sort(key=lambda row: (row[0], row[8] != "", row[3], row[4], row[5]))
with open(dst, "w", encoding="utf-8", newline="\n") as handle:
    handle.write("# numeric\tmcc\tmnc\tcarrier\tapn\ttype\tprotocol\troaming_protocol\tmvno_type\tmvno_match_data\n")
    for row in rows:
        handle.write("\t".join(row) + "\n")

print(f"wrote {dst}: {len(rows)} rows, {os.path.getsize(dst)} bytes")
