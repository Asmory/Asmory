# Asmory theming

Asmory currently ships two first-class website themes.

## Obsidian Gold

The dark theme is the default design language for low-level/HPC work:

- near-black backgrounds;
- graphite panels;
- warm gold accents;
- high-contrast terminal surfaces.

## Ivory Alloy

The light theme is intentionally not a simple color inversion:

- warm engineering-paper background;
- ivory surfaces;
- dark graphite text;
- restrained bronze/gold accents.

## Behavior

The Registry and GitHub Pages site follow the same policy:

1. a manually selected theme stored in `localStorage` wins;
2. otherwise the browser's `prefers-color-scheme` is used;
3. the toggle persists across visits.

The storage key is:

```text
asmory-theme
```

Supported values:

```text
dark
light
```

Registry theming is implemented in:

```text
registry/static/app.css
registry/static/app.js
```

GitHub Pages theming is implemented in:

```text
site/style.css
site/theme.js
```

## Light-theme contrast policy

Asmory follows a stricter contrast rule for the light theme:

- ordinary text on light surfaces always uses dark semantic colors;
- secondary text uses graphite gray rather than pale gray;
- light foreground colors are only allowed on deliberately dark surfaces;
- terminals remain dark in both themes for stable syntax/terminal contrast;
- bronze primary buttons explicitly pair a dark-enough surface with light text.

This prevents dark-theme hardcoded foreground colors from leaking onto light
surfaces.
