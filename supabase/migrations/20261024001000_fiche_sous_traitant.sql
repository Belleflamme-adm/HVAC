-- Fiche du sous-traitant (ADR-064) : responsable, propriétaire, coordonnées du responsable.
-- La fiche se modifie par la planification (Simon, Mike, coordination) : politique maj_planif existante.
alter table public.fournisseurs
  add column responsable_nom       text check (length(responsable_nom) <= 120),
  add column responsable_telephone text check (length(responsable_telephone) <= 40),
  add column responsable_courriel  text check (responsable_courriel ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  add column proprietaire_nom      text check (length(proprietaire_nom) <= 120);
-- Numéro de licence RBQ : 10 chiffres, écrit 1234-5678-90 (format vérifié aussi côté serveur)
alter table public.fournisseurs
  add constraint fournisseurs_licence_rbq_format check (licence_rbq is null or licence_rbq ~ '^\d{4}-\d{4}-\d{2}$') not valid;

-- Renseignements personnels (Loi 25) : chaque modification de la fiche est journalisée
create trigger trg_audit after insert or update on public.fournisseurs for each row execute function app.audit();
