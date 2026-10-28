-- Module Lightroom Classic pour fusionner les doublons et réduire les rafales.

return {
  LrSdkVersion = 10.0,
  LrSdkMinimumVersion = 6.0,
  LrToolkitIdentifier = 'fr.matthieu.deduplicate',
  LrPluginName = 'Deduplicate',
  LrInitPlugin = 'Initialiser.lua',
  LrEnablePlugin = 'Initialiser.lua',
  LrShutdownPlugin = 'Arreter.lua',
  LrDisablePlugin = 'Arreter.lua',
  LrLibraryMenuItems = {
    { title = 'Fusionner les doublons…', file = 'FusionnerDoublons.lua' },
    { title = 'Fusionner de force la sélection…', file = 'FusionManuelle.lua' },
    { title = 'Réduire les rafales…', file = 'ReduireRafales.lua' },
  },
  VERSION = { major = 26, minor = 10, revision = 0 },
}
