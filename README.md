# bg-generation-composition

Small Zig project that generates an SVG composition based on a grid of geometric tiles and a small SDL3 pattern editor.

The output is a centered black-on-cream composition inspired by Yvaral's "Composition en noir".

## What It Does

Running the CLI writes a single SVG file containing the pattern from `pattern.txt`.

Running the editor opens an SDL3 window that previews the composition, lets you click cells to change tile variants, resize the grid, zoom and pan the canvas, and save both the pattern file and an exported SVG.

## Requirements

- Zig `0.16.0` or newer

Dependencies are managed by Zig through [`build.zig.zon`](/Users/ebernard/Documents/tools/bg-generation-composition/build.zig.zon). The project depends on [`zsvg`](https://github.com/edmBernard/zsvg) for SVG document generation and SDL3 for the native editor.

## Build

Build the executable with:

```bash
zig build
```

The binary is installed to:

```text
zig-out/bin/bg_generation_composition
```

## Usage

Run with the default output path:

```bash
zig build run
```

This creates:

```text
output.svg
```

The CLI always reads the current pattern from:

```text
pattern.txt
```

Pass a custom output path after `--`:

```bash
zig build run -- artwork.svg
```

You can also run the built binary directly:

```bash
./zig-out/bin/bg_generation_composition artwork.svg
```

On success, the program prints the written file path to stderr.

## Development

Run tests with:

```bash
zig build test
```

Run the SDL editor with:

```bash
zig build editor
```

Pattern files now save with an explicit size header:

```text
size=15
0 0 0 ...
```

Legacy headerless `15x15` files are still supported when loading.

Editor shortcuts:

- `LMB` / `RMB`: cycle the hovered tile forward or backward
- `Mouse wheel` or `+` / `-`: zoom
- `MMB drag` or `Space` + `LMB drag`: pan
- `0`: fit the pattern to the preview
- `Arrow keys`: pan the viewport
- `S`: save `pattern.txt`
- `E`: export `pattern.svg`
- `R`: reload `pattern.txt`
- `Q`: quit

Editor controls:

- HUD `Grid -/+`: shrink or grow the square grid while preserving the top-left content
- HUD `Zoom -/+`: adjust zoom around the preview center
- HUD `Fit` / `Reset`: restore a safe viewport if the pattern moves off-screen

## Notes

It's a toy project. And lot's of stuff are vibe coded, so if you spot error, improvement comments are welcomed.
