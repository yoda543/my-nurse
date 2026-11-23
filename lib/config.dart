/// Configuration de l'app, modifiable à la compilation :
///
///   flutter run --dart-define=DEMO=true      (données de démonstration)
///   flutter run                               (base Supabase my-nurse)
library;

/// Mode démonstration : tout en mémoire, sans compte ni réseau.
const demoMode = bool.fromEnvironment('DEMO');

/// Projet Supabase. La clé publiable peut figurer dans l'app : les règles
/// d'accès de la base protègent les données.
const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://brqzagwexxesowihehjt.supabase.co',
);
const supabaseKey = String.fromEnvironment(
  'SUPABASE_KEY',
  defaultValue: 'sb_publishable_Qx1aIp069hqJHOemASpthA_L8AX-GN7',
);
