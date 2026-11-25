# Migrations en attente (ne pas appliquer automatiquement)

Ces fichiers sont hors de `supabase/migrations/` exprès : ils ne s'appliquent
qu'une fois l'app mise à jour.

| Fichier | Quand | Effet |
|---|---|---|
| `0014_lock_patient_medical_columns.sql` | Après la sortie de l'app qui lit et écrit `medical_records` (étape B) | Les colonnes médicales de `patients` ne sont plus lisibles par l'API ; fin de la recopie |
| `0015_drop_patient_medical_columns.sql` | 30 jours après 0014, sauvegarde faite (étape C) | **Destructif** : supprime `patients.allergies`, `history`, `treatments` |

Pour appliquer : déplacer le fichier dans `supabase/migrations/` puis le pousser.
