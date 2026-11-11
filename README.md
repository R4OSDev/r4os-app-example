# EXAMPLE.R4X

`EXAMPLE.R4X` is an independent R4OS application implemented in Zig.

## Package

- Version: `0.1.10`
- Image target: `/R4OS/SOFTWARE/DESKTOP/EXAMPLE.R4X`
- Image scope: `full`
- Canonical project manifest: `module.R4MF`

The manifest is the single source of truth for the artifact, imports, image
target, and package metadata.

## Build

On Windows:

    Build.bat

On Linux or macOS:

    ./Build.sh

The build starters resolve the current local R4OS dependency checkouts through
`Settings.R4S`. The URL and hash entries in `build.zig.zon` record the
last verified standalone dependency identities; workspace builds use the
mapped local checkouts.

## Documentation

Detailed German technical notes from the migration are preserved in
`DOCUMENTATION.de.txt`. Source-transfer provenance is recorded in
`PROVENANCE.txt`.

## License

Original R4OS material is licensed under Apache License 2.0. See `LICENSE`
and `NOTICE`. Any repository-specific external material is documented in
`THIRD_PARTY_NOTICES.md`.

0.85.44: Rebuilt with SDK0.64.57 and the shared R4STD Unicode17.0.0
extended grapheme editing boundaries. Byte offsets, scalar font advances
and grapheme clusters are distinct; no shaping or BiDi support is implied.

API migration 0.90.68
---------------------
New projects can follow this manifest's SDK_PROFILE=r4os-zig-generation2,
Query2 platform imports and r4_app_main(*r4os.App2). Build source pins match
the normal SDK201/Contract93 selection. The shared Window owns event/paint
lifetime. Font changes rebuild layout. Temporary display labels use the
shared whole-grapheme UTF8 presentation helper. Editable values remain in
their existing TextField. The three static file-dialog rows demonstrate the
widget interface and keep their synthetic selection behavior.
