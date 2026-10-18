# Figma Codegen Reference

**PENTING:** File-file di direktori ini adalah **REFERENSI SAJA**, bukan kode produksi.

## Isi

- `theme_reference/` — Token warna/shape/theme yang di-export dari Figma (sudah diekstrak ke `lib/core/theme/`)
- `code_gen_export/` — Layout & komponen UI yang di-generate dari Figma
- `l10n_reference/` — File localization hasil codegen (tidak digunakan dalam arsitektur)
- Utility files — `auto_size_text.dart`, `design_frame_widget.dart`, dll. (tidak untuk produksi)

## Cara Menggunakan

### ✅ DO:
1. **Ekstrak design tokens** (warna, spacing, radius) → sudah dipindah ke `lib/core/theme/`
2. **Gunakan sebagai referensi visual** saat membangun screen asli
3. **Lihat struktur layout** untuk memahami hierarki UI dari Figma
4. **Identifikasi komponen** yang perlu dibangun ulang dengan Flutter yang proper

### ❌ DON'T:
1. **Jangan copy-paste** file codegen langsung ke `lib/`
2. **Jangan pakai** `Stack` + `Positioned` absolute dari codegen
3. **Jangan pakai** `.wdp`, `.hdp`, `DesignFrameWidget`, atau `AutoSizeText`
4. **Jangan pakai** layout yang tidak responsif terhadap text scale besar

## Prinsip Implementasi

Saat membangun screen dari referensi Figma:

1. **Baca frame yang relevan** dari `code_gen_export/interactive_preview/features/`
2. **Identifikasi komponen visual** (button, card, list, form field)
3. **Tulis ulang** menggunakan:
   - `Column`, `Row`, `ListView`, `Expanded`, `Padding`
   - Token dari `lib/core/theme/`
   - Widget Flutter standard yang responsif
4. **Pastikan accessible** dengan text scale 1.0-2.0

## Struktur Screen yang Tersedia

Cek `code_gen_export/interactive_preview/features/` untuk melihat screen mana yang ada referensi Figma-nya.

---

**Diperbarui:** Oktober 2026
