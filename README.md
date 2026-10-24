# Save Value Viewer (asset mirror)

A read-only viewer for Godot settings and save files. It adds a **Value Viewer** tab to the
editor, lists every value in a `ConfigFile` (`.cfg`, `.ini`) or JSON file, and lets you filter,
inspect and copy them. It never writes to the file.

Free and open source (MIT). Built and exercised on Godot 4.5.2, 4.6.3 and 4.7.2 (Windows 11);
Godot 4.5 or newer is the supported range.

This repository exists so the Godot Asset Library can serve the add-on archive. The add-on lives in
`addons/save_value_viewer/`; the archive the editor installs is attached to the releases
(`save-value-viewer-<version>-library.zip`) and contains only that folder plus its licence.

- Godot Asset Store: <https://store.godotengine.org/asset/onpont/save-value-viewer/>
- Editing values, reviewing the change set and restoring a backup: [Save Value Editor](https://onpont.itch.io/save-value-editor), a separate paid tool.

## Install

Copy `addons/save_value_viewer/` into your project (or let the editor install the release archive),
then enable **Save Value Viewer** in *Project > Project Settings > Plugins*.

## Limits

UTF-8 (optional BOM), at most 8 MiB, 20,000 listed entries. Encrypted or binary files, JSON Lines and
arbitrary serialisation formats are out of scope. Values are displayed as the file stores them; the
viewer never rewrites the file, so it cannot corrupt it.

See `addons/save_value_viewer/README.md` for the operation guide.
