# HelpCenterBackup

`HelpCenterBackup` is a native macOS app for downloading and maintaining backups of Intercom Help Center articles.

## Features

- Backs up articles in nested folders:
- `Help Center -> Collection -> Sub-Collection/Section -> Article`
- Export formats:
- `JSON`, `MARKDOWN (.md)`, `HTML`, `PDF`, `TXT`
- Image handling:
- Optional image download with local asset references
- Download modes:
- `Full Download` and `Updates Only` (incremental)
- Incremental metadata file:
- `.backup_metadata.json`
- Backup history log with timestamps:
- `.backup_history.log`
- In-app README viewer:
- `Read Me` link (bottom-left)

## Requirements

- macOS 13 or newer
- Intercom API key/token with Help Center read access

## Usage

1. Open the app.
2. In `Options`, enter your Intercom API key.
3. Choose an output folder.
4. Select file type and backup options.
5. Click `Run Backup`.

## Output

- Article files are written into nested category folders.
- Metadata and logs are written to the selected output folder:
- `.backup_metadata.json`
- `.backup_history.log`

## Build From Source

1. Open this project in Xcode.
2. Select the `HelpCenterBackupApp` scheme.
3. Run.

## Package App + DMG

From the project root:

```bash
./scripts/package-macos.sh /path/to/icon.jpg /path/to/background.jpg
```

- First argument: app icon source image.
- Second argument: DMG background image.
- Version is controlled in `scripts/package-macos.sh` via `APP_VERSION`.
