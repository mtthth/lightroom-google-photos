-- Module Lightroom Classic :
--   - recrée les albums Google Photos sous forme de collections, à partir du fichier
--     photos-albums-<année>.csv produit par export-albums.mjs ;
--   - fusionne les doublons du catalogue (fichiers identiques importés plusieurs fois) ;
--   - réduit les rafales d'un dossier (garde le cadre le plus net de chaque bloc de 4) ;
--   - service d'export « Google Photos », qui envoie des photos dans un album Google Photos
--     (préréglage « Google Photos 4K » dans le dossier presets).

return {
  LrSdkVersion = 10.0,
  LrSdkMinimumVersion = 6.0,
  LrToolkitIdentifier = 'fr.matthieu.albumsgooglephotos',
  LrPluginName = 'Albums Google Photos',
  LrInitPlugin = 'Initialiser.lua',
  LrEnablePlugin = 'Initialiser.lua',
  LrShutdownPlugin = 'Arreter.lua',
  LrDisablePlugin = 'Arreter.lua',
  LrLibraryMenuItems = {
    { title = 'Recréer les albums Google Photos…', file = 'RecreerAlbums.lua' },
    { title = 'Fusionner les doublons…', file = 'FusionnerDoublons.lua' },
    { title = 'Fusionner de force la sélection…', file = 'FusionManuelle.lua', enabledWhen = 'photosSelected' },
    { title = 'Réduire les rafales…', file = 'ReduireRafales.lua' },
  },
  LrExportServiceProvider = {
    title = 'Google Photos',
    file = 'ServiceGooglePhotos.lua',
    builtInPresetsDir = 'presets',
  },
  VERSION = { major = 1, minor = 5, revision = 0 },
}
