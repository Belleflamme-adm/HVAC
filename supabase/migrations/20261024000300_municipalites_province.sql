-- Est de l'Ontario dans la carte du territoire (ADR-053) : chaque municipalité porte sa province.
-- Les codes ontariens sont préfixés « ON- » et ne peuvent pas entrer en collision avec les codes du Québec.
alter table public.municipalites add column province text not null default 'QC'
  check (province in ('QC','ON'));
alter table public.municipalites add constraint municipalites_code_province
  check ((province = 'ON') = (code like 'ON-%'));
alter table public.municipalites alter column source set default 'Découpages administratifs, MRNF (CC-BY 4.0)';
