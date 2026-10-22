-- Numéro de devis : même série que l'app de Mike (Simon, 22 oct. 2026) :
-- entier global, sans préfixe ni année, affiché « #120815 ».
--
-- Point de départ : tant que l'app HVAC est autonome et sur données fictives, le compteur part
-- de 900001 pour qu'aucun devis de démonstration ne porte le numéro d'un vrai devis de Mike.
-- À la greffe, le compteur est aligné sur le prochain numéro réel de Mike (docs/MIGRATION.md).
update public.formats_numerotation
   set modele = '{seq}', prefixe = '', portee = 'globale',
       description = 'Même série que l''app de Mike (#120815). Départ de démo : 900001, aligné à la greffe.'
 where cle = 'devis';

insert into public.compteurs (cle, periode, prochain) values ('devis', '*', 900001)
on conflict (cle, periode) do update set prochain = greatest(public.compteurs.prochain, 900001);
