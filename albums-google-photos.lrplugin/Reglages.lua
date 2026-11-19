-- Réglages du module, dans Fichier → Gestionnaire de modules externes → Albums Google Photos.
local LrPrefs = import 'LrPrefs'
local LrView = import 'LrView'
local Langue = require 'Langue'
local T = Langue.t

return {
  sectionsForTopOfDialog = function(f, proprietes)
    local prefs = LrPrefs.prefsForPlugin()
    proprietes.langue = prefs.langue == 'en' and 'en' or 'fr'
    proprietes:addObserver('langue', function(_, _, valeur) prefs.langue = valeur end)
    local langues = {}
    for i, l in ipairs(Langue.LANGUES) do langues[i] = { title = l.nom, value = l.code } end
    return { {
      title = T('Langue', 'Language'),
      bind_to_object = proprietes,
      f:row {
        f:static_text { title = T('Langue de l’interface :', 'Interface language:'), width_in_chars = 22 },
        f:popup_menu { items = langues, value = LrView.bind('langue') },
      },
      f:static_text {
        title = T('Vaut pour les dialogues et l’export dès la commande suivante. Le titre du menu suit la langue de '
          .. 'Lightroom. Les noms des collections créées par le module ne changent pas.',
          'Applies to dialogs and export from the next command on. The menu title follows Lightroom’s language. '
          .. 'The names of the collections created by the plug-in do not change.'),
        width = 450, height_in_lines = 3,
      },
    } }
  end,
}
