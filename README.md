# HelpCenterBackupMacApp

A native macOS SwiftUI app that downloads an incremental backup of Intercom Help Center articles.

## What it does

- Fetches help centers, collections, and articles from Intercom.
- Saves articles as `json`, `md`, `html`, or `pdf` files in a folder hierarchy:
  - Help Center -> Collection(s) -> Section/Subsection(s) -> Article file
- Tracks article `updated_at` in `.backup_metadata.json`.
- On later runs, only rewrites new/updated articles (incremental backup).

## Requirements

- macOS 13+
- Xcode 15+ (recommended)
- Intercom API key/token with Help Center read access

## Run in Xcode

1. Open Xcode.
2. `File -> Open...`
3. Select `/Users/samuelhuang/Desktop/Scripts/HelpCenterBackupMacApp`.
4. Choose the `HelpCenterBackupApp` scheme.
5. Press Run.

## Usage

1. Paste your Intercom API key.
2. Choose an output folder.
3. Choose file type: `JSON`, `MARKDOWN`, `HTML`, or `PDF`.
4. Choose whether to include images.
5. Click **Start Backup**.

The app stores your last API key, output folder, file type, and image preference in local app preferences.

## Export options

- `JSON`: structured article payload with `bodyHTML`, `bodyText`, and downloaded image paths.
- `MARKDOWN`: markdown file with article metadata, text body, and optional image links.
- `HTML`: HTML file preserving body markup. If images are included, image URLs are rewritten to local downloaded files.
- `PDF`: text-based PDF export for each article.

When **Include Images** is on, images are downloaded into an adjacent `*_assets` folder per article.

## Notes

- API base URL is `https://api.intercom.io`.
- API version header is set to `2.14`.
- Article backup metadata is written to: `<output folder>/.backup_metadata.json`.
