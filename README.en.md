# Google Photos Albums for Lightroom Classic

*[Version française](README.md)*

A **Lightroom Classic** plug-in (Windows) with companion Node scripts that bridges your catalog and Google Photos,
without going through Takeout:

- **Recreates your Google Photos albums as Lightroom collections**, grouped by year
  (`Google Photos - albums / 2025 / 2025-07-24 – Week-end à Lyon`), and finds in the catalog the originals of photos
  that Google only keeps as downsized copies.
- **Groups photos by period**: for each album, every catalog photo taken during the same period, plus filler
  collections for the gaps between two periods.
- **Retrieves missing photos**: photos from shared albums, or never synced with Lightroom, are downloaded in original
  quality, ready to import.
- **Exports a collection to a Google Photos album** from Lightroom's export dialog, through the official API, with
  photo resizing and 1080p video conversion.

Updates are incremental: only new or changed albums are read again, and existing collections are completed, never
duplicated.

> The plug-in interface and the full user guide ([LISEZ-MOI.md](LISEZ-MOI.md)) are in French; this page summarises
> what it does and how to get started.

## Requirements

- Lightroom Classic on **Windows**.
- **Node 22 or later** ([nodejs.org](https://nodejs.org/)) and **Google Chrome**.
- **ffmpeg**: optional, to convert videos on export (`winget install Gyan.FFmpeg`).
- For exporting to Google Photos only: a Google Cloud project with your own OAuth client (the steps are at the top of
  `connexion-google-photos.mjs`).

## Installation

1. Download the latest version from [Releases](../../releases) and unzip it **in full** into a folder you can write
   to: the plug-in uses the scripts and files that sit next to its own folder.
2. In Lightroom Classic: **File → Plug-in Manager → Add**, then choose the `albums-google-photos.lrplugin` folder.

## Getting started

1. In the project folder, read your Google Photos albums:

   ```powershell
   node export-albums.mjs
   ```

   The first time, a Chrome window opens: sign in to your Google account. The session is kept in a dedicated Chrome
   profile.
2. In Lightroom: **Library → Plug-in Extras → Recréer les albums Google Photos…** (recreate Google Photos albums),
   then choose `photos-albums-tous.csv`.
3. If some photos are missing from the catalog, run `node telecharger-manquantes.mjs`, import the
   `photos-albums-tous-manquantes` folder, then run step 2 again.

## Limitations and precautions

- **Windows only**: Chrome, Lightroom and the working folders are looked up in their Windows locations.
- **French interface and documentation.**
- **Albums are read through an undocumented interface.** Since March 2025, the official Google Photos API no longer
  gives access to a user's albums, so `export-albums.mjs` and `telecharger-manquantes.mjs` read the Google Photos
  website through your Chrome session. They may stop working if Google changes its site, and this use is not
  endorsed by Google. Exporting to Google Photos, on the other hand, uses the official API.
- **The export connection must be renewed**: while your OAuth client stays in "Testing" mode, Google drops the
  connection after 7 days; Lightroom then offers to reconnect.
- **Export can only add to albums it created** (a Google API restriction).
- The plug-in creates and completes collections; it never removes a photo from the catalog nor deletes an original.
  As with any tool that touches a catalog, **back up your catalog** before the first run.

Your exports (CSV), downloaded photos and OAuth credentials stay on your machine, in the project folder and in
`%LOCALAPPDATA%\lightroom-google-photos`; they are excluded from Git.

## Optional companion plug-in

[Deduplicate](https://github.com/mtthth/lightroom-deduplicate) merges duplicates and thins out bursts. Installed in
two sibling folders, `lightroom-google-photos` (keep this name) and `lightroom-deduplicate`, the two plug-ins share
the history of discarded photos: photos removed by Deduplicate do not come back in albums, periods or downloads.
This plug-in also works on its own; if you add Deduplicate later, run it once before recreating the albums.

## Tests

```powershell
node tests/lancer.mjs             # Lua and JavaScript suites (Node 22+, MiKTeX texlua)
node tests/lancer.mjs --js        # JavaScript only, without MiKTeX
node tests/lancer.mjs --mutants   # tests, then five controlled regressions
```

The tests run outside Lightroom against a fake Lightroom and synthetic data: they do not open Chrome, call Google,
or touch your catalog or exports.

## License

[MIT](LICENSE). Changes are listed in the [changelog](CHANGELOG.md) (in French).
