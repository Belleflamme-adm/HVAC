-- Installation : décisions de Simon du 22 oct. 2026.
--   * marge par défaut : 25 % du prix de vente (fixée et ajustable par Simon et Mike)
--   * installation faite UNIQUEMENT par des sous-traitants : sous-traitant obligatoire,
--     même pour une soumission. Une liste de prix interne sera créée si ça change.

update public.parametres
   set valeur = '2500',
       description = 'Marge sur le prix de vente de l''installation, en points de base (2500 = 25 %). Fixée par Simon et Mike.'
 where cle = 'marge_installation_bp' and valeur = '3000'::jsonb;

create or replace function app.marge_installation_bp() returns integer
language sql stable as $$
  select coalesce((select (valeur #>> '{}')::int from public.parametres where cle = 'marge_installation_bp'), 2500)
$$;

alter table public.devis_lignes drop constraint devis_lignes_installation_chk;
alter table public.devis_lignes add constraint devis_lignes_installation_chk check (
  type_ligne <> 'installation'
  or (type_travail_id is not null and sous_traitant_id is not null and produit_id is null and kit_id is null));
