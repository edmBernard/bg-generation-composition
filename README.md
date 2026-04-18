# bg-generation-composition

Small Zig project that generates an SVG composition based on a fixed grid of geometric tiles.

The output is a centered black-on-cream composition inspired by Yvaral's "Composition en noir".

## What It Does

Running the executable writes a single SVG file containing the pattern.

## Requirements

- Zig `0.16.0` or newer

Dependencies are managed by Zig through [`build.zig.zon`](/Users/ebernard/Documents/tools/bg-generation-composition/build.zig.zon). The project depends on [`zsvg`](https://github.com/edmBernard/zsvg) for SVG document generation.

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

## Notes

It's a toy project. And lot's of stuff are vibe coded, so if you spot error, improvement comments are welcomed.
