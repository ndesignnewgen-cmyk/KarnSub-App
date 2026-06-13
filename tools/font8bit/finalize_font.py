# -*- coding: utf-8 -*-
"""Set final name + OFL metadata on the finished font.

Usage: python finalize_font.py <in.ttf> <out.ttf>
"""
import sys

from fontTools.ttLib import TTFont

FAMILY = "KarnSub Lao Round"
PS = "KarnSubLaoRound-Regular"
COPYRIGHT = ("Derived from Noto Sans Lao Looped (Copyright 2022 The Noto "
             "Project Authors). Modified by KarnSub. Licensed under the SIL "
             "Open Font License 1.1.")
LICENSE_URL = "https://scripts.sil.org/OFL"

src, dst = sys.argv[1], sys.argv[2]
f = TTFont(src)
name = f["name"]


def setn(nid, value):
    name.setName(value, nid, 3, 1, 0x409)   # Windows / Unicode / en-US
    name.setName(value, nid, 1, 0, 0)        # Mac / Roman / en


setn(0, COPYRIGHT)
setn(1, FAMILY)
setn(2, "Regular")
setn(4, FAMILY)
setn(6, PS)
setn(13, "This Font Software is licensed under the SIL Open Font License, "
        "Version 1.1. No Reserved Font Names.")
setn(14, LICENSE_URL)
setn(16, FAMILY)
setn(17, "Regular")
for nid in (3,):
    name.removeNames(nameID=nid)

f.save(dst)
print(f"finalized -> {dst}  (family='{FAMILY}')")
