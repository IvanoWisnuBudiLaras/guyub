# Design System — Guyub.id

Sumber kebenaran tunggal untuk semua design tokens dalam aplikasi.

## Struktur

```
lib/core/theme/
├── theme.dart              # Barrel export (gunakan ini)
├── app_theme.dart          # ThemeData Material 3
├── app_colors.dart         # Palet warna
├── app_text_styles.dart    # Typography scale
├── app_spacing.dart        # Spacing tokens
└── app_radius.dart         # Border radius tokens
```

## Penggunaan

### Import

```dart
import 'package:guyub_id/core/theme/theme.dart';
```

### Warna

```dart
// Gunakan dari ColorScheme
Container(
  color: Theme.of(context).colorScheme.primary,
  child: Text(
    'Hello',
    style: TextStyle(
      color: Theme.of(context).colorScheme.onPrimary,
    ),
  ),
)

// Atau langsung dari AppColors untuk kasus khusus
Container(color: AppColors.gray200)
```

### Typography

```dart
// Gunakan dari TextTheme
Text(
  'Heading',
  style: Theme.of(context).textTheme.headlineMedium,
)

// Atau langsung dari AppTextStyles
Text('Body', style: AppTextStyles.bodyMedium)
```

### Spacing

```dart
Padding(
  padding: EdgeInsets.all(AppSpacing.md),
  child: Column(
    spacing: AppSpacing.sm,
    children: [...],
  ),
)
```

### Border Radius

```dart
Container(
  decoration: BoxDecoration(
    borderRadius: AppRadius.lgRadius,
    color: Colors.blue,
  ),
)
```

## Prinsip

1. **Jangan hardcode** nilai warna, spacing, atau radius
2. **Gunakan token** dari design system ini
3. **Responsive by default** — pastikan UI scale dengan text size
4. **Dark mode ready** — semua warna sudah didefinisikan untuk light & dark

## Design Tokens

### Warna Neutral
- `black` — #000000
- `gray900` — #121212
- `gray800` — #222222
- `gray200` — #E5E5E5
- `white` — #FFFFFF

### Warna Brand
- `primary` — #D85A30
- `primaryDark` — #D6592E

### Spacing Scale
- `xs` — 4dp
- `sm` — 8dp
- `md` — 16dp
- `lg` — 24dp
- `xl` — 32dp
- `xxl` — 48dp

### Border Radius
- `sm` — 8dp
- `md` — 12dp
- `lg` — 14.7dp
- `xl` — 16dp
- `xxl` — 24dp
- `full` — 9999dp (circle)

---

**Sumber:** Token diekstrak dari Figma (lihat `docs/figma_export/theme_reference/`)
