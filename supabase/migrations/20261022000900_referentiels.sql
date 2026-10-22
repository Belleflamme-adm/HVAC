-- Phase 1 | Données de référence (configuration, pas des données de démo).

insert into public.succursales (code, nom, ville, est_entrepot) values
  ('HO', 'Head Office | Saint-Jérôme (succursale et entrepôt central)', 'Saint-Jérôme', true),
  ('ST', 'St-Sauveur',    'Saint-Sauveur', false),
  ('RO', 'Rosemère',      'Rosemère',      false),
  ('DR', 'Drummondville', 'Drummondville', false),
  ('GA', 'Gatineau',      'Gatineau',      false);

insert into public.divisions (nom, lettre, code_generique, est_hvac) values
  ('Ventilation',   'V', 'VTC', true),
  ('Climatisation', 'V', 'VTC', true),
  ('Foyer',         'F', 'FYR', false),
  ('Foyer-Gaz',     'F', 'FYG', false),
  ('Gaz',           'F', 'FYG', false),
  ('BBQ',           'B', 'BBQ', false);

insert into public.taux_taxes (code, taux_pcm, en_vigueur_du) values
  ('TPS', 5000, '2008-01-01'),
  ('TVQ', 9975, '2013-01-01');

-- Formats provisoires : à remplacer par ceux de Mike (ADR-004), sans migration de données.
insert into public.formats_numerotation (cle, modele, prefixe, portee, description) values
  ('devis',       '{prefixe}-{annee}-{seq:5}', 'D',   'annuelle',  'Provisoire. Format de Mike à confirmer.'),
  ('facture',     '{prefixe}-{annee}-{seq:5}', 'F',   'annuelle',  'Provisoire. Série unique, sans trou.'),
  ('note_credit', '{prefixe}-{annee}-{seq:5}', 'NC',  'annuelle',  'Provisoire. Série distincte des factures, à confirmer.'),
  ('projet',      '{succ}{div}-{seq:3}-{aa}',  '',    'succursale_annuelle', 'Provisoire. Format XXX-XXX-XXX de Mike à confirmer (2e et 3e segments inconnus).'),
  ('bt',          '{prefixe}-{annee}-{seq:5}', 'BT',  'annuelle',  'Provisoire.'),
  ('asv',         '{prefixe}-{annee}-{seq:5}', 'ASV', 'annuelle',  'Appel de service ventilation. Provisoire.'),
  ('contrat',     '{prefixe}-{annee}-{seq:4}', 'CE',  'annuelle',  'Contrat d''entretien. Provisoire.');

insert into public.parametres (cle, valeur, description) values
  ('bloquer_certifs_expirees', 'false', 'Refuser l''assignation d''un BT si une certification est expirée (ADR-015).'),
  ('bloquer_facture_logisvert_incomplete', 'true', 'Refuser l''émission d''une facture de solde ou finale si une pièce LogisVert manque (ADR-008).'),
  ('delai_solde_heures', '72', 'Le solde est dû X heures avant l''installation (ADR-009).');
