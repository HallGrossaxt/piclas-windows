#!/usr/bin/env python3
"""patch_cuda_comdat.py — Remove COMDAT from .bss sections in a CUDA COFF object.

Background
----------
nvcc (using cl.exe as host compiler) emits two MSVC C++ function-local static
variables in COMDAT BSS sections inside each CUDA TU object file:

  ?__ref@?1??____nv_dummy_param_ref@@YAXPEAX@Z@4PEAPECXEA
  ?__ref@?2??__nv_cudaEntityRegisterCallback@@YAXPEAPEAX@Z@4PEAPECXEA

GNU ld (MinGW) discards these LINK_ONCE_DISCARD COMDAT sections, leaving the
IMAGE_REL_AMD64_REL32 relocations in ?__sti____cudaRegisterAll resolved to 0.
A displacement of 0 causes `mov %rax, 0x0(%rip)` to write the CUDA fat-binary
handle into the read-only .text section → ACCESS VIOLATION at DLL load time
(reported as STATUS_DLL_INIT_FAILED / error 1114).

Root cause
----------
GNU ld determines COMDAT status from TWO places:
  1. IMAGE_SCN_LNK_COMDAT (0x1000) flag in the section header Characteristics
  2. The 'Selection' byte (offset 14) of the auxiliary symbol record attached
     to the section symbol in the COFF symbol table

Both must be cleared; clearing only the section flag is insufficient.

Fix
---
For every .bss COMDAT section:
  a) Clear IMAGE_SCN_LNK_COMDAT from the section header Characteristics.
  b) Find the matching section symbol in the COFF symbol table (scl=3, nx≥1,
     SectionNumber == this section's 1-based index).
  c) Zero the Selection byte in the auxiliary symbol record.

GNU ld then treats the section as regular BSS and always includes it, so the
IMAGE_REL_AMD64_REL32 relocations resolve to valid BSS addresses.

Usage
-----
  python3 patch_cuda_comdat.py <input.obj> [output.obj]

If output.obj is omitted the input file is patched in-place.
"""

import sys
import struct

IMAGE_SCN_LNK_COMDAT = 0x00001000
IMAGE_SYM_CLASS_STATIC = 3


def patch_coff_comdat_bss(data: bytes) -> bytes:
    """Return a copy of the COFF object with COMDAT cleared from .bss sections."""
    if len(data) < 20:
        raise ValueError("File is too small to be a COFF object")

    # COFF file header (20 bytes)
    machine, nsections, _ts, sym_ptr, nsyms, opt_size, _chars = \
        struct.unpack_from('<HHIIIHH', data, 0)

    if machine != 0x8664:
        print(f"[patch_cuda_comdat] WARNING: machine type 0x{machine:04x} "
              f"(expected 0x8664 / x86-64)", file=sys.stderr)

    buf = bytearray(data)
    section_table_offset = 20 + opt_size

    # Collect 1-based section indices of .bss COMDAT sections and patch
    # their section header Characteristics.
    comdat_bss_sections = set()   # 1-based section numbers

    for i in range(nsections):
        hdr_off = section_table_offset + i * 40
        if hdr_off + 40 > len(buf):
            break

        name_raw = buf[hdr_off: hdr_off + 8]
        name = name_raw.split(b'\x00')[0].decode('ascii', errors='replace')

        chars_off = hdr_off + 36
        sec_chars = struct.unpack_from('<I', buf, chars_off)[0]

        if name == '.bss' and (sec_chars & IMAGE_SCN_LNK_COMDAT):
            new_chars = sec_chars & ~IMAGE_SCN_LNK_COMDAT
            struct.pack_into('<I', buf, chars_off, new_chars)
            sec_num = i + 1   # 1-based
            comdat_bss_sections.add(sec_num)
            print(f"[patch_cuda_comdat]  sec hdr {sec_num:3d} ({name}): "
                  f"cleared COMDAT  0x{sec_chars:08x} -> 0x{new_chars:08x}")

    # Now clear the COMDAT Selection byte from auxiliary symbol records for
    # each patched section.
    #
    # COFF symbol table: each entry is 18 bytes.  If NumberOfAuxSymbols (nx)
    # is 1 for a section symbol (scl=3), the next 18-byte slot is the
    # auxiliary record with layout:
    #   [0..3]  SizeOfBlock    (4 bytes)
    #   [4..5]  NumRelocations (2 bytes)
    #   [6..7]  NumLineNumbers (2 bytes)
    #   [8..11] CheckSum       (4 bytes)
    #   [12..13]Number         (2 bytes) — section number for ASSOCIATIVE
    #   [14]    Selection      (1 byte)  ← COMDAT selection type; set to 0
    #   [15..17]Unused         (3 bytes)

    if comdat_bss_sections and sym_ptr and nsyms:
        sym_base = sym_ptr
        sym_idx = 0
        aux_patched = 0
        while sym_idx < nsyms:
            sym_off = sym_base + sym_idx * 18
            if sym_off + 18 > len(buf):
                break

            # Symbol entry:
            #   [0..7]   Name (8 bytes; or zeroes + 4-byte string-table offset)
            #   [8..11]  Value  (4 bytes)
            #   [12..13] SectionNumber (2 bytes, signed)
            #   [14..15] Type   (2 bytes)
            #   [16]     StorageClass (1 byte)
            #   [17]     NumberOfAuxSymbols (1 byte)
            sec_num_s = struct.unpack_from('<h', buf, sym_off + 12)[0]
            scl      = buf[sym_off + 16]
            nx       = buf[sym_off + 17]

            if (scl == IMAGE_SYM_CLASS_STATIC and nx >= 1
                    and sec_num_s > 0
                    and sec_num_s in comdat_bss_sections):
                # Auxiliary record immediately follows this symbol entry.
                aux_off = sym_base + (sym_idx + 1) * 18
                if aux_off + 18 <= len(buf):
                    old_sel = buf[aux_off + 14]
                    if old_sel != 0:
                        buf[aux_off + 14] = 0
                        aux_patched += 1
                        print(f"[patch_cuda_comdat]  sym aux  {sym_idx:4d}: "
                              f"cleared COMDAT Selection {old_sel} -> 0 "
                              f"(sec {sec_num_s})")

            sym_idx += 1 + nx   # advance past this symbol + its aux records

        print(f"[patch_cuda_comdat]  {aux_patched} auxiliary COMDAT record(s) cleared")

    print(f"[patch_cuda_comdat] Patched {len(comdat_bss_sections)} COMDAT .bss "
          f"section(s) out of {nsections} total sections")
    return bytes(buf)


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <input.obj> [output.obj]", file=sys.stderr)
        sys.exit(1)

    infile = sys.argv[1]
    outfile = sys.argv[2] if len(sys.argv) > 2 else infile

    with open(infile, 'rb') as fh:
        data = fh.read()

    patched = patch_coff_comdat_bss(data)

    with open(outfile, 'wb') as fh:
        fh.write(patched)

    if outfile == infile:
        print(f"[patch_cuda_comdat] Patched in-place: {infile}")
    else:
        print(f"[patch_cuda_comdat] Written to: {outfile}")


if __name__ == '__main__':
    main()
