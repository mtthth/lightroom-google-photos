-- Module Lightroom Classic pour recréer et exporter les albums Google Photos.

return {
  LrSdkVersion = 10.0,
  LrSdkMinimumVersion = 6.0,
  LrToolkitIdentifier = 'io.github.mtthth.albumsgooglephotos',
  LrPluginName = 'Albums Google Photos',
  LrPluginInfoProvider = 'Reglages.lua',
  -- Le titre du menu suit la langue de Lightroom (TranslatedStrings_en.txt), pas le réglage du module :
  -- Lightroom le lit avant que le module puisse consulter ses préférences.
  LrLibraryMenuItems = {
    { title = LOC '$$$/AlbumsGooglePhotos/Menu/Recreer=Recréer les albums Google Photos…', file = 'RecreerAlbums.lua' },
  },
  LrExportServiceProvider = {
    title = 'Google Photos',
    file = 'ServiceGooglePhotos.lua',
    builtInPresetsDir = 'presets',
  },
  VERSION = { major = 1, minor = 1, revision = 0 },
}
