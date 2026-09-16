-- osm-target - English. Every player-facing string lives here; translate or
-- reword by copying this file to <lang>.lua and setting Config.Locale.

Locales = Locales or {}

Locales['en'] = {
  -- These are what an unmodified legacy resource gains for free: its declared
  -- item and job gates become readable requirements instead of a vanished row.
  requires_item = 'Requires %s',
  requires_item_count = 'Requires %s x%s',
  requires_items_all = 'Requires %s',
  requires_items_any = 'Requires %s or %s',
  requires_group = '%s only',
  requires_group_grade = '%s (rank %s) only',
  requires_group_any = '%s only',
  unavailable = 'Unavailable',
  not_eligible = 'You cannot do this',

  -- Built-in vehicle door labels (Config.Defaults.vehicleDoors)
  door_front_driver = 'Toggle front driver door',
  door_front_passenger = 'Toggle front passenger door',
  door_rear_driver = 'Toggle rear driver door',
  door_rear_passenger = 'Toggle rear passenger door',
  door_hood = 'Toggle hood',
  door_trunk = 'Toggle trunk',

  go_back = 'Back',
  no_options = 'Nothing to do here',
  toggle_targeting = 'Interact (osm-target)',

  admin_no_perm = 'You do not have permission to do that.',
  admin_ingame_only = '/%s must be run in-game.',
  admin_loading = 'Configuration is still loading, try again in a moment.',
  admin_saved = 'Interaction settings saved and applied to everyone.',
  admin_reverted = 'Design reverted to its shipped defaults.',
  admin_imported = 'Configuration imported.',
  admin_import_failed = 'That configuration blob could not be read.',
  prefs_saved = 'Preferences saved.',
  debug_on = 'Target debug enabled.',
  debug_off = 'Target debug disabled.',
  debug_required = 'Enable diagnostics first with /%s.',
  test_spawned = 'Test subject spawned in front of you. /%s off removes it.',
  test_removed = 'Test subject removed.',
  test_none = 'There is no test subject to remove.',
  test_failed = 'The test subject could not be spawned.',

  -- Only ever seen through /targettest; kept here so the sample menu is
  -- translated with everything else.
  test_talk = 'Talk',
  test_talk_desc = 'A plain, always-available option.',
  test_search = 'Search pockets',
  test_search_desc = 'Carries a description, so the plate has two lines.',
  test_cuff = 'Restrain',
  test_fine = 'Issue fine',
  test_medical = 'Medical',
  test_pulse = 'Check pulse',
  test_treat = 'Treat wounds',
  test_move = 'Move along',
  test_move_reason = 'They have nowhere else to be',
  test_selected = 'Test option: %s',

  -- Submenu reference set (/targettest fridge).
  test_fridge = 'Fridge',
  test_fridge_logger = 'Logger Beer',
  test_fridge_lavazas = 'Lavazas Beer',
  test_fridge_berry = 'Blitz Berry Smoothie',
  test_fridge_green = 'Blitz Green Smoothie',
  test_fridge_protein = 'Protein Shake',
  test_fridge_protein_reason = 'Someone finished it',

  version_outdated = 'osm-target %s is available (running %s).',
}
