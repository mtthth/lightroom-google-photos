-- Module Lightroom Classic pour recréer et exporter les albums Google Photos.

return {
  LrSdkVersion = 10.0,
  LrSdkMinimumVersion = 6.0,
  LrToolkitIdentifier = 'fr.matthieu.albumsgooglephotos',
  LrPluginName = 'Albums Google Photos',
  LrLibraryMenuItems = {
    { title = 'Recréer les albums Google Photos…', file = 'RecreerAlbums.lua' },
  },
  LrExportServiceProvider = {
    title = 'Google Photos',
    file = 'ServiceGooglePhotos.lua',
    builtInPresetsDir = 'presets',
  },
  VERSION = { major = 26, minor = 10, revision = 0 },
}
