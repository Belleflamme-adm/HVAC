-- Code projet Belleflamme : [SUCC][DIV]-[PRÉ]-[NOM]-[NNN]
\set ON_ERROR_STOP on
set client_min_messages = notice;

select test.ok(app.code3('Pierre-Luc') = 'PIE', 'prénom composé : PIE');
select test.ok(app.code3('Émilie') = 'EMI', 'accents retirés : EMI');
select test.ok(app.code3('Lévesque') = 'LEV', 'LEV');
select test.ok(app.code3('O''Brien') = 'OBR', 'apostrophe retirée : OBR');
select test.ok(app.code3('Li') = 'LIX', 'nom de 2 lettres complété : LIX');
select test.ok(app.code3('Œuvre') = 'OEU', 'ligature Œ : OEU');

insert into public.clients(id, prenom, nom, succursale_code) values
  ('31000000-0000-0000-0000-000000000001','Jean','Tremblay','ST'),
  ('31000000-0000-0000-0000-000000000002','Jeanne','Tremblay','ST');
insert into public.clients(id, nom, entreprise, type, succursale_code) values
  ('31000000-0000-0000-0000-000000000003','Gagnon','Constructions Éco','entreprise','ST');

insert into public.devis(id, succursale_code, client_id, vendeur_id) values
  ('43000000-0000-0000-0000-000000000001','ST','31000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000c'),
  ('43000000-0000-0000-0000-000000000002','ST','31000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000c'),
  ('43000000-0000-0000-0000-000000000003','ST','31000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-00000000000c'),
  ('43000000-0000-0000-0000-000000000004','ST','31000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-00000000000c');
select test.ok((select code_projet = 'STV-JEA-TRE-001' from public.devis where id = '43000000-0000-0000-0000-000000000001'), '1er devis : STV-JEA-TRE-001');
select test.ok((select code_projet = 'STV-JEA-TRE-002' from public.devis where id = '43000000-0000-0000-0000-000000000002'), '2e devis du même client : 002');
select test.ok((select code_projet = 'STV-JEA-TRE-003' from public.devis where id = '43000000-0000-0000-0000-000000000003'),
               'Jeanne Tremblay (même préfixe) : 003, jamais un doublon');
select test.ok((select code_projet = 'STV-CON-GAG-001' from public.devis where id = '43000000-0000-0000-0000-000000000004'),
               'entreprise sans prénom : le nom de l''entreprise remplace le prénom');
select test.echec($$update public.devis set code_projet = 'X' where id = '43000000-0000-0000-0000-000000000001'$$, 'modifier un code projet');
select test.echec($$update public.devis set client_id = '31000000-0000-0000-0000-000000000002' where id = '43000000-0000-0000-0000-000000000001'$$,
                  'changer le client d''un devis', 'ne se change pas');

insert into public.projets(id, succursale_code, client_id, devis_id) values
  ('72000000-0000-0000-0000-000000000001','ST','31000000-0000-0000-0000-000000000001','43000000-0000-0000-0000-000000000002');
select test.ok((select code_projet = 'STV-JEA-TRE-002' from public.projets where id = '72000000-0000-0000-0000-000000000001'),
               'le projet reprend le code du devis accepté');
select test.ok((select code_projet is not null from public.devis_v where id = '43000000-0000-0000-0000-000000000001'), 'vue devis_v : code projet exposé');

\echo 'TESTS CODE PROJET PASSÉS'

-- Extensions (renouvellements)
select public.hvac_dupliquer_devis('43000000-0000-0000-0000-000000000001') as ext1 \gset
select test.ok((select code_projet = 'STV-JEA-TRE-001-E01' and devis_origine_id = '43000000-0000-0000-0000-000000000001'
                  from public.devis where id = :'ext1'), 'renouvellement : STV-JEA-TRE-001-E01');
select public.hvac_dupliquer_devis(:'ext1') as ext2 \gset
select test.ok((select code_projet = 'STV-JEA-TRE-001-E02' and devis_origine_id = '43000000-0000-0000-0000-000000000001'
                  from public.devis where id = :'ext2'), 'renouvellement d''une extension : E02, rattaché à l''origine');
select public.hvac_dupliquer_devis('43000000-0000-0000-0000-000000000002') as ext3 \gset
select test.ok((select code_projet = 'STV-JEA-TRE-002-E01' from public.devis where id = :'ext3'),
               'chaque devis d''origine a ses propres extensions : 002-E01');
insert into public.devis(succursale_code, client_id, vendeur_id) values
  ('ST','31000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-00000000000c');
select test.ok((select max(code_projet) = 'STV-JEA-TRE-004' from public.devis where code_projet not like '%-E%' and client_id = '31000000-0000-0000-0000-000000000001'),
               'un nouveau devis (pas un renouvellement) continue la série : 004');
select test.echec(format($$update public.devis set devis_origine_id = null where id = %L$$, :'ext1'), 'détacher une extension de son origine');

\echo 'TESTS EXTENSIONS PASSÉS'
