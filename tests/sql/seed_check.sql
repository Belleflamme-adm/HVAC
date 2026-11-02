-- Vérifie que le seed de démo se charge et produit des données cohérentes.
\set ON_ERROR_STOP on
set client_min_messages = notice;
do $$
declare n int;
begin
  select count(*) into n from public.clients;  if n <> 6 then raise exception 'clients: %', n; end if;
  if not exists (select 1 from public.devis where numero = '900001' and statut = 'accepte') then
    raise exception 'devis 1 attendu accepté et numéroté'; end if;
  if not exists (select 1 from public.devis_lignes where approbation_requise) then
    raise exception 'le devis de démo 2 doit attendre une approbation'; end if;
  if not exists (select 1 from public.factures where numero like 'F-%-00001' and statut = 'payee') then
    raise exception 'facture de dépôt attendue émise et payée'; end if;
  if not exists (select 1 from public.projets where code_projet = 'ROV-JUL-TRE-001') then
    raise exception 'projet ROV-JUL-TRE-001 attendu'; end if;
  if exists (select 1 from public.produits where not fictif) then raise exception 'produit non marqué FICTIF'; end if;
  if not exists (select 1 from public.devis_lignes where type_ligne = 'installation' and prix_unitaire_cents = 86667) then
    raise exception 'installation de démo attendue : 650 $ avec marge 25 %% = 866,67 $'; end if;
  if not exists (select 1 from public.bons_travail where numero = 'RV001 ROV-JUL-TRE-001' and statut = 'brouillon') then
    raise exception 'BT RV001 brouillon attendu'; end if;
  if not exists (select 1 from public.bons_commande where numero = 'ROV-JUL-TRE-100' and statut = 'brouillon') then
    raise exception 'BC ROV-JUL-TRE-100 brouillon attendu (fournisseur de la marque)'; end if;
  raise notice 'ok | seed de démo cohérent';
end $$;
