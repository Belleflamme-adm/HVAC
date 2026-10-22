-- CRM : type de demande et qualifications des vendeurs (ADR-058).
\set ON_ERROR_STOP on
set client_min_messages = notice;

-- 95_crm : c et d actifs, e inactif ; tous qualifiés pour tout (migration). On précise les qualifications :
delete from public.crm_vendeur_types;
insert into public.crm_vendeur_types(employe_id, type_demande) values
  ('00000000-0000-0000-0000-00000000000c','mural_simple'), ('00000000-0000-0000-0000-00000000000c','mural_multi'),
  ('00000000-0000-0000-0000-00000000000d','mural_simple'), ('00000000-0000-0000-0000-00000000000d','central'),
  ('00000000-0000-0000-0000-00000000000d','bienergie');

insert into public.leads(id, succursale_code, source, contact_nom, type_demande) values
  ('a6000000-0000-0000-0000-000000000001','RO','google','Central 1','central'),
  ('a6000000-0000-0000-0000-000000000002','RO','google','Central 2','central'),
  ('a6000000-0000-0000-0000-000000000003','RO','google','Multi 1','mural_multi');
select test.ok((select bool_and(assigne_a = '00000000-0000-0000-0000-00000000000d') from public.leads
                 where id in ('a6000000-0000-0000-0000-000000000001','a6000000-0000-0000-0000-000000000002')),
               'système central : seulement le vendeur qualifié (d), même deux fois de suite');
select test.ok((select assigne_a = '00000000-0000-0000-0000-00000000000c' from public.leads where id = 'a6000000-0000-0000-0000-000000000003'),
               'mural multi : seulement le vendeur qualifié (c)');

-- Mural simple : c et d qualifiés, tour de rôle propre à ce type
insert into public.leads(id, succursale_code, source, contact_nom, type_demande) values
  ('a6000000-0000-0000-0000-000000000004','RO','google','Simple 1','mural_simple'),
  ('a6000000-0000-0000-0000-000000000005','RO','google','Simple 2','mural_simple'),
  ('a6000000-0000-0000-0000-000000000006','RO','google','Simple 3','mural_simple');
select test.ok((select array_agg(right(assigne_a::text, 1) order by id) = array['c','d','c'] from public.leads
                 where id in ('a6000000-0000-0000-0000-000000000004','a6000000-0000-0000-0000-000000000005','a6000000-0000-0000-0000-000000000006')),
               'mural simple : tour de rôle c, d, c entre les qualifiés');

-- Personne de qualifié : non attribué, visible du board seulement
delete from public.crm_vendeur_types where type_demande = 'bienergie';
insert into public.leads(id, succursale_code, source, contact_nom, type_demande) values
  ('a6000000-0000-0000-0000-000000000007','RO','google','Biénergie','bienergie');
select test.ok((select assigne_a is null and attribue_le is null from public.leads where id = 'a6000000-0000-0000-0000-000000000007'),
               'biénergie sans vendeur qualifié : non attribué (on ne brûle pas le client)');

-- Type inconnu : tous les vendeurs actifs
insert into public.leads(id, succursale_code, source, contact_nom) values
  ('a6000000-0000-0000-0000-000000000008','RO','google','Inconnu');
select test.ok((select assigne_a is not null from public.leads where id = 'a6000000-0000-0000-0000-000000000008'),
               'type inconnu : tour de rôle entre tous les vendeurs actifs');

-- Vue : avertit si le vendeur assigné n'est pas qualifié
set role authenticated;
select test.comme('00000000-0000-0000-0000-00000000000a');
update public.leads set assigne_a = '00000000-0000-0000-0000-00000000000c' where id = 'a6000000-0000-0000-0000-000000000001';
select test.ok((select not vendeur_qualifie from public.leads_v where id = 'a6000000-0000-0000-0000-000000000001'),
               'Simon peut forcer, mais la vue signale un vendeur non qualifié');
select test.comme('00000000-0000-0000-0000-00000000000c');
select test.echec($$update public.leads set type_demande = 'mural_simple' where id = 'a6000000-0000-0000-0000-000000000001'$$,
                  'un vendeur change le type de son lead', 'type');
delete from public.crm_vendeur_types where employe_id = '00000000-0000-0000-0000-00000000000c';
reset role;
reset request.jwt.claims;
select test.ok((select count(*) = 2 from public.crm_vendeur_types where employe_id = '00000000-0000-0000-0000-00000000000c'),
               'un vendeur ne retire pas ses propres qualifications');

\echo 'TESTS TYPES DE DEMANDE PASSÉS'
