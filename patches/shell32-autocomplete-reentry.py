#!/usr/bin/env python3
"""Patch the engine's 32-bit shell32.dll (CrossOver 24.0.7 / Wine 9.0 build).

Usage: shell32-autocomplete-reentry.py <original shell32.dll> <output shell32.dll>

Input  sha256: 4e9465e555e41849ad11...  (lib/wine/i386-windows/shell32.dll)
Output sha256: 025a29b60988b232101e2256bda89c9d51098bd356dda9449bd330e1d6ba649b

Fault: dlls/shell32/autocomplete.c, display_matching_strs(). With
ACO_AUTOAPPEND | ACO_AUTOSUGGEST it appends the suggestion with WM_SETTEXT.
If the program sets the text again while it handles that change (eApp's masked
text boxes do), the second WM_SETTEXT reaches the autocomplete subclass, which
frees the string list (hide_listbox(reset) -> free_enum_strs). Back in
display_matching_strs, find_matching_enum_str() reads the freed list and the
process dies with a page fault at shell32+0x894c.

Change: the second find_matching_enum_str() call (0x1000a0ab) goes through a
22-byte stub placed in alignment padding at 0x1000aa8a. The stub checks that
ac->enum_strs is still the list saved before the text was set. If not, it
leaves display_matching_strs() with TRUE and shows no list.
"""
import struct
import sys

BASE, TEXT_VA, TEXT_RAW = 0x10000000, 0x1000, 0x1000
CAVE, FUNC, EXIT, CALLSITE = 0x1000AA8A, 0x10008910, 0x1000983D, 0x1000A0AB


def off(va):
    return va - BASE - TEXT_VA + TEXT_RAW


d = bytearray(open(sys.argv[1], "rb").read())
padding = bytes.fromhex("2e8db42600000000" * 2 + "8db600000000")
assert d[off(CAVE):off(CAVE) + 22] == padding, "unexpected bytes in the padding gap"
assert d[off(CAVE) - 2:off(CAVE)] == b"\xeb\x16", "padding gap is not jumped over"
assert d[off(CALLSITE)] == 0xE8
assert struct.unpack("<i", d[off(CALLSITE) + 1:off(CALLSITE) + 5])[0] == FUNC - (CALLSITE + 5)

stub = bytearray()
stub += bytes.fromhex("8d0cba")  # lea (%edx,%edi,4),%ecx   current list + start
stub += bytes.fromhex("39ce")    # cmp %ecx,%esi            same as the saved list + start?
stub += bytes.fromhex("8d4f01")  # lea 1(%edi),%ecx         restore the start argument
stub += b"\x0f\x84" + struct.pack("<i", FUNC - (CAVE + len(stub) + 6))  # je find_matching_enum_str
stub += bytes.fromhex("83c8ff")  # or $-1,%eax              list changed: return TRUE
stub += b"\xe9" + struct.pack("<i", EXIT - (CAVE + len(stub) + 5))      # jmp function exit
assert len(stub) == 22

d[off(CAVE):off(CAVE) + 22] = stub
d[off(CALLSITE) + 1:off(CALLSITE) + 5] = struct.pack("<i", CAVE - (CALLSITE + 5))
open(sys.argv[2], "wb").write(d)
