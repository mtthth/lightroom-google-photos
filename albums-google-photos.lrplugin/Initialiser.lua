local LrPathUtils = import 'LrPathUtils'
require('Annulation').demarrer(LrPathUtils.child(LrPathUtils.parent(_PLUGIN.path), 'photos-traitees.txt'))
