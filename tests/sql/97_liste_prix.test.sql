-- Liste de prix des sous-traitants (ADR-060)
\set ON_ERROR_STOP on
set client_min_messages = notice;
select test.ok((select count(*) = 68 from public.types_travaux where categorie is not null), '68 travaux classés par catégorie');
select test.ok((select unite = 'tete' and categorie = 'murale' from public.types_travaux where code = 'INST-TETE-MULTI'),
               'INST-TETE-MULTI (code de Mike) : par tête, thermopompe murale');
select test.ok((select count(*) = 4 from public.types_travaux where code in ('INST-MULTI-2T','INST-MULTI-3T','INST-MULTI-4T','INST-MULTI-5T')),
               'multizone 2, 3, 4 et 5 têtes énumérées une par une');
select test.ok((select count(*) = 0 from public.types_travaux t left join public.categories_travaux c on c.code = t.categorie
                 where t.categorie is not null and c.code is null), 'chaque catégorie existe');
select test.echec($$insert into public.types_travaux(code, nom, unite) values ('X-TEST','Test','par semaine')$$, 'unité inconnue');
\echo 'TESTS LISTE DE PRIX PASSÉS'
