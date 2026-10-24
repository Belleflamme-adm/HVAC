// Tableau marketing (ADR-072, ADR-073 : rendement sur la marge, budget prévu par source) : d'où viennent les leads, ce qu'ils coûtent, ce qu'ils rapportent, par source, campagne,
// secteur et auditoire, pour décider où mettre le budget. Données FICTIVES tant que Monday, Facebook et Google ne sont pas branchés.
// Loi 25 : aucun genre ni âge au dossier d'un lead ; l'auditoire vient des rapports agrégés des plateformes.
import { initPage } from './bf-page.js?v=0.4.0';
import { h, remplir } from './bf-dom.js?v=0.4.0';
import { voitBoard } from './bf-crm.js?v=0.4.0';
import { creerCarte, chargerMunicipalites, chargerReperes } from './bf-carte.js?v=0.4.0';
import { SUCCURSALES, moisJusqua, indexVilles } from './bf-ventes-fictives.js?v=0.4.0';
import { SOURCES, CAMPAGNES, CAMPAGNES_PAYANTES, TYPES_DEMANDE, GENRES, AGES, JOURS_SEMAINE, JOURS_LONGS, BUDGET_DEFAUT, marketingFictif } from './bf-marketing-fictif.js?v=0.4.0';
import { SEQ, compact, entier, pctTxt, dollars, montrerBulle, cacherBulle, survol, carteGraph, vide, tuile, barres,
  colonnesEmpilees, lignes, anneau, celluleSeq, panneauDash } from './bf-dash.js?v=0.4.0';

const FIN = '2026-10';
const PERIODES = {
  '12m': { libelle: '12 derniers mois', mois: moisJusqua(FIN, 12), avant: moisJusqua('2025-10', 12), compare: 'vs 12 mois précédents' },
  '3m': { libelle: '3 derniers mois', mois: moisJusqua(FIN, 3), avant: moisJusqua('2026-07', 3), compare: 'vs 3 mois précédents' },
  mois: { libelle: 'Octobre 2026', mois: [FIN], avant: ['2026-09'], compare: 'vs septembre' },
  annee: { libelle: 'Année 2026 (à ce jour)', mois: moisJusqua(FIN, 10), avant: moisJusqua('2025-10', 10), compare: 'vs même période 2025' },
};
const SERIES_SOURCES = Object.entries(SOURCES).map(([cle, s]) => ({ cle, libelle: s.libelle, couleur: s.couleur }));
const COULEUR_GENRE = { femmes: 'var(--d-s3)', hommes: 'var(--d-s2)', inconnu: '#6b7790' };
const PLAGES = [[6, 9, '6 h à 9 h'], [9, 12, '9 h à midi'], [12, 15, 'midi à 15 h'], [15, 18, '15 h à 18 h'], [18, 21, '18 h à 21 h'], [21, 24, '21 h à minuit'], [0, 6, 'nuit']];

// Indicateurs d'un ensemble de leads et de dépenses. Coût par lead, coût par vente et rendement : sur les leads des
// campagnes payées seulement (une référence gratuite ne doit pas faire paraître une pub plus rentable qu'elle ne l'est).
function kpi(leads, depenses) {
  const dep = depenses.reduce((s, d) => s + d.depense_cents, 0) / 100;
  const ventes = leads.filter((l) => l.vendu);
  const valeur = ventes.reduce((s, l) => s + l.valeur_cents, 0) / 100;
  const payes = leads.filter((l) => CAMPAGNES_PAYANTES.has(l.campagne));
  const ventesPayees = payes.filter((l) => l.vendu);
  const valeurPayee = ventesPayees.reduce((s, l) => s + l.valeur_cents, 0) / 100;
  const margePayee = ventesPayees.reduce((s, l) => s + l.marge_cents, 0) / 100;
  return {
    leads: leads.length, depense: dep, visites: leads.filter((l) => l.visite).length, contactes: leads.filter((l) => l.contacte).length,
    ventes: ventes.length, valeur, conv: leads.length ? ventes.length / leads.length : null, payes: payes.length,
    cpl: dep && payes.length ? dep / payes.length : null, cpv: dep && ventesPayees.length ? dep / ventesPayees.length : null,
    rendement: dep ? valeurPayee / dep : null, valeurPayee,
    // Rendement sur la marge : marge brute (avec installation) des ventes issues des campagnes payées, par 1 $ dépensé
    rendementMarge: dep ? margePayee / dep : null, margePayee, marge: ventes.reduce((s, l) => s + l.marge_cents, 0) / 100,
    clics: depenses.reduce((s, d) => s + d.clics, 0), impressions: depenses.reduce((s, d) => s + d.impressions, 0),
  };
}
const rendementTxt = (r) => (r === null ? 'sans coût' : `${r.toLocaleString('fr-CA', { maximumFractionDigits: 1 })} $`);
const nd = (v, f) => (v === null || v === undefined ? 'n/d' : f(v));

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  if (!voitBoard(user)) {
    remplir(zone, h('h1', {}, 'Tableau marketing'), h('p', { class: 'bf-message' }, 'Réservé à la direction et aux gérants.'));
  } else {
    const donnees = marketingFictif(FIN);
    const [geo, reperes] = await Promise.all([chargerMunicipalites(), chargerReperes()]);
    const codeVille = indexVilles(geo);
    const filtres = { periode: '12m', succursale: '', source: '', type: '' };
    // Budget mensuel prévu par source (recalcul différé : le champ modifié est remplacé par le nouvel affichage). Maquette : gardé dans ce navigateur seulement ; dans l'app branchée, en base.
    const CLE_BUDGET = 'bf_budget_marketing';
    let budget = { ...BUDGET_DEFAUT };
    try { const b = JSON.parse(localStorage.getItem(CLE_BUDGET) || 'null'); if (b) budget = { ...budget, ...b }; } catch { /* stockage indisponible */ }
    const sauverBudget = () => { try { localStorage.setItem(CLE_BUDGET, JSON.stringify(budget)); } catch { /* stockage indisponible */ } };
    let editionBudget = false;
    const choix = (nom, libelle, options) => {
      const sel = h('select', { 'aria-label': libelle }, options.map(([v, t]) => h('option', { value: v, selected: filtres[nom] === v }, t)));
      sel.addEventListener('change', () => { filtres[nom] = sel.value; rendre(); });
      return sel;
    };
    const barreFiltres = h('div', { class: 'bf-dash__filtres' },
      choix('periode', 'Période', Object.entries(PERIODES).map(([k, p]) => [k, p.libelle])),
      choix('succursale', 'Succursale', [['', 'Toutes les succursales'], ...Object.entries(SUCCURSALES).map(([k, s]) => [k, s.nom])]),
      choix('source', 'Source', [['', 'Toutes les sources'], ...Object.entries(SOURCES).map(([k, s]) => [k, s.libelle])]),
      choix('type', 'Type de demande', [['', 'Tous les types'], ...Object.entries(TYPES_DEMANDE)]));
    const corps = h('div', { class: 'bf-dash__corps' });
    remplir(zone, panneauDash('Vue exécutive | Marketing',
      'D\'où viennent les leads, ce qu\'ils coûtent, ce qu\'ils rapportent : pour décider où et vers qui envoyer le budget.', barreFiltres, corps));

    let carte = null; let densite = new Map(); let classe = () => 0;
    const zoneCarte = h('div', { class: 'bf-dash__carte-geo' });

    function rendre() {
      cacherBulle();
      const P = PERIODES[filtres.periode];
      // Les dépenses suivent la source et la succursale... sauf qu'une campagne couvre plusieurs succursales :
      // avec une succursale choisie, la dépense est répartie au prorata de ses leads (approximation affichée).
      const garderLead = (l) => (!filtres.succursale || l.succursale === filtres.succursale) && (!filtres.source || l.source === filtres.source) && (!filtres.type || l.type === filtres.type);
      const baseLeads = donnees.leads.filter(garderLead);
      const tousCamp = donnees.leads.filter((l) => !filtres.source || l.source === filtres.source);
      const partDepense = (mois, campagne) => {
        if (!filtres.succursale && !filtres.type) return 1;
        const tous = tousCamp.filter((l) => l.mois === mois && l.campagne === campagne).length;
        const gardes = baseLeads.filter((l) => l.mois === mois && l.campagne === campagne).length;
        return tous ? gardes / tous : 0;
      };
      const baseDep = donnees.depenses.filter((d) => !filtres.source || d.source === filtres.source)
        .map((d) => { const f = partDepense(d.mois, d.campagne); return f === 1 ? d : { ...d, depense_cents: d.depense_cents * f, clics: d.clics * f, impressions: d.impressions * f }; });
      const dansP = (x) => P.mois.includes(x.mois); const avantP = (x) => P.avant.includes(x.mois);
      const leads = baseLeads.filter(dansP); const dep = baseDep.filter(dansP);
      const K = kpi(leads, dep); const A = kpi(baseLeads.filter(avantP), baseDep.filter(avantP));
      const delta = (a, b) => (a === null || b === null || !b ? null : (a - b) / b);
      const gratuits = leads.filter((l) => !SOURCES[l.source].payante || l.campagne === 'autres-tel').length;

      // Par source et par campagne
      const parSource = Object.entries(SOURCES).map(([k, s]) => ({ k, s, K: kpi(leads.filter((l) => l.source === k), dep.filter((d) => d.source === k)) })).filter((x) => x.K.leads || x.K.depense);
      const parCampagne = CAMPAGNES.map((c) => ({ c, K: kpi(leads.filter((l) => l.campagne === c.code), dep.filter((d) => d.campagne === c.code)) })).filter((x) => x.K.leads || x.K.depense);
      // Mois (12) pour les graphiques
      const mois12 = moisJusqua(FIN, 12);
      const leadsMois = mois12.map((m) => Object.fromEntries(SERIES_SOURCES.map((se) => [se.cle, baseLeads.filter((l) => l.mois === m && l.source === se.cle).length])));
      const payantes = ['facebook', 'google', 'instagram'].filter((s) => !filtres.source || s === filtres.source);
      const cplMois = Object.fromEntries(payantes.map((s) => [s, mois12.map((m) => {
        const k = kpi(baseLeads.filter((l) => l.mois === m && l.source === s), baseDep.filter((d) => d.mois === m && d.source === s)); return k.leads ? k.cpl : null;
      })]));
      // Secteurs (succursales)
      const parSucc = Object.entries(SUCCURSALES).map(([k, s]) => ({ k, s, l: leads.filter((x) => x.succursale === k) })).filter((x) => x.l.length);
      densite = new Map();
      for (const l of leads) for (const c of codeVille(l.succursale, l.municipalite)) densite.set(c, (densite.get(c) || 0) + 1);
      const maxD = Math.max(1, ...densite.values());
      const bornes = [0.2, 0.4, 0.6, 0.8].map((q) => Math.max(1, Math.round(maxD * q)));
      classe = (n) => bornes.filter((b) => n > b).length;   // la carte, créée une fois, lit toujours les bornes courantes
      // Auditoire (agrégé, plateformes payantes seulement)
      const aud = donnees.auditoire.filter((a) => dansP(a) && (!filtres.source || a.source === filtres.source));
      const parGenre = Object.entries(GENRES).map(([k, lib]) => { const l = aud.filter((a) => a.genre === k); return { k, lib, leads: l.reduce((s, a) => s + a.leads, 0), dep: l.reduce((s, a) => s + a.depense_cents, 0) / 100, ventes: l.reduce((s, a) => s + a.ventes, 0) }; });
      const parAge = AGES.map((age) => { const l = aud.filter((a) => a.age === age); return { age, leads: l.reduce((s, a) => s + a.leads, 0), dep: l.reduce((s, a) => s + a.depense_cents, 0) / 100, ventes: l.reduce((s, a) => s + a.ventes, 0) }; });
      // Entonnoir
      const etapes = [['Leads reçus', K.leads], ['Contactés', K.contactes], ['Visites faites', K.visites], ['Ventes', K.ventes]];
      // Quand arrivent les leads : jour x plage horaire
      const grille = JOURS_SEMAINE.map((_, j) => PLAGES.map(([a, b]) => leads.filter((l) => l.jour_semaine === j && l.heure >= a && l.heure < b).length));
      const maxG = Math.max(1, ...grille.flat());
      // Types de demande par source
      const typesVus = filtres.type ? [filtres.type] : Object.keys(TYPES_DEMANDE);
      const matrice = parSource.map(({ k }) => typesVus.map((t) => leads.filter((l) => l.source === k && l.type === t).length));
      const maxM = Math.max(1, ...matrice.flat());

      // Budget prévu vs dépensé : par source, toutes succursales (le budget est global)
      const sourcesBudget = Object.keys(SOURCES).filter((k) => !filtres.source || k === filtres.source);
      const depGlobal = donnees.depenses.filter((d) => dansP(d) && sourcesBudget.includes(d.source));
      const parBudget = sourcesBudget.map((k) => ({ k, s: SOURCES[k], prevu: (Number(budget[k]) || 0) * P.mois.length,
        depense: depGlobal.filter((d) => d.source === k).reduce((t, d) => t + d.depense_cents, 0) / 100 })).filter((x) => x.prevu || x.depense);
      const prevuTotal = parBudget.reduce((t, x) => t + x.prevu, 0); const depTotal = parBudget.reduce((t, x) => t + x.depense, 0);
      const budgetMois = mois12.map((m) => sourcesBudget.reduce((t, k) => t + (Number(budget[k]) || 0), 0));
      const depMois = mois12.map((m) => donnees.depenses.filter((d) => d.mois === m && sourcesBudget.includes(d.source)).reduce((t, d) => t + d.depense_cents, 0) / 100);
      const etatBudget = (x) => (!x.prevu ? (x.depense ? 'hors' : 'ok') : x.depense / x.prevu > 1.05 ? 'depasse' : x.depense / x.prevu < 0.85 ? 'sous' : 'ok');

      remplir(corps,
        h('div', { class: 'bf-dash__tuiles bf-dash__tuiles--5' },
          tuile('leads', 'Leads reçus', entier(K.leads), delta(K.leads, A.leads), P.compare),
          tuile('porte_voix', 'Dépenses marketing', compact(K.depense), delta(K.depense, A.depense), P.compare, { hausseBonne: false }),
          tuile('cible', 'Budget prévu', compact(prevuTotal), null, '', { note: prevuTotal ? `${pctTxt(depTotal / prevuTotal)} utilisé (${compact(depTotal)}), toutes succursales` : 'aucun budget inscrit' }),
          tuile('cible', 'Coût par lead', K.depense ? nd(K.cpl, dollars) : 'sans coût', delta(K.cpl, A.cpl), P.compare, { hausseBonne: false, note: `${entier(K.payes)} leads de campagnes payées` }),
          tuile('vente', 'Taux de conversion', nd(K.conv, (v) => pctTxt(v, 1)), K.conv !== null && A.conv !== null ? K.conv - A.conv : null, P.compare,
            { points: true, note: `${entier(K.ventes)} ventes sur ${entier(K.leads)} leads` }),
          tuile('argent', 'Coût par vente', K.depense ? nd(K.cpv, dollars) : 'sans coût', delta(K.cpv, A.cpv), P.compare, { hausseBonne: false }),
          tuile('machines', 'Ventes générées', compact(K.valeur), delta(K.valeur, A.valeur), P.compare),
          tuile('rendement', 'Rendement', K.depense ? rendementTxt(K.rendement) : 'sans coût', delta(K.rendement, A.rendement), P.compare,
            { note: 'de ventes pour chaque 1 $ dépensé' }),
          tuile('marge', 'Rendement sur la marge', K.depense ? rendementTxt(K.rendementMarge) : 'sans coût', delta(K.rendementMarge, A.rendementMarge), P.compare,
            { note: `de marge brute pour chaque 1 $ dépensé (${compact(K.margePayee)} de marge)` }),
          tuile('carte', 'Leads sans coût', pctTxt(K.leads ? gratuits / K.leads : 0), null, '', { note: 'références, appels et visites en magasin' })),

        h('div', { class: 'bf-dash__rangee bf-dash__rangee--2-1' },
          carteGraph('Leads par mois et par source', filtres.periode === '12m' ? '12 derniers mois' : `12 derniers mois | ${P.libelle} en plein`,
            ...colonnesEmpilees({ mois: mois12, series: SERIES_SOURCES, valeurs: leadsMois, unite: 'leads', enPlein: (m) => P.mois.includes(m), aria: 'Leads par mois et par source' })),
          carteGraph('D\'où viennent les leads', P.libelle,
            anneau(SERIES_SOURCES.map((se) => ({ ...se, n: leads.filter((l) => l.source === se.cle).length })), { centre: entier(K.leads), unite: 'leads', aria: 'Répartition des leads par source' }))),

        h('div', { class: 'bf-dash__rangee bf-dash__rangee--2-1' },
          carteGraph('Coût par lead par mois', '12 derniers mois | sources payantes',
            ...(payantes.length ? lignes({ mois: mois12, valeurs: cplMois, pasAxe: 20, format: (v) => dollars(v), enPlein: (m) => P.mois.includes(m),
              series: payantes.map((s) => ({ cle: s, libelle: SOURCES[s].libelle, couleur: SOURCES[s].couleur })), aria: 'Coût par lead par mois et par source payante' })
              : [vide('Aucune source payante dans ce filtre.')])),
          carteGraph('Rendement sur la marge par source', `${P.libelle} | marge brute pour chaque 1 $ dépensé`,
            barres(parSource.filter((x) => x.K.depense).sort((a, b) => b.K.rendementMarge - a.K.rendementMarge).map(({ s, K: k }) => ({
              libelle: s.libelle, sous: `${compact(k.depense)} dépensés | ${compact(k.margePayee)} de marge | ventes : ${rendementTxt(k.rendement)} par 1 $`,
              valeur: k.rendementMarge, texte: rendementTxt(k.rendementMarge), couleur: s.couleur,
              bulle: [[rendementTxt(k.rendement), 'de ventes par 1 $'], [nd(k.cpl, dollars), 'par lead'], [nd(k.cpv, dollars), 'par vente'], [nd(k.conv, (v) => pctTxt(v, 1)), 'des leads achètent']] }))),
            h('p', { class: 'bf-dash__muet' }, 'Marge brute avec installation, sur les leads des campagnes payées. Les références, les appels et les visites en magasin sont « sans coût ».'))),

        h('div', { class: 'bf-dash__rangee bf-dash__rangee--1-2' },
          carteGraph('Budget prévu et dépensé, par source', `${P.libelle} | toutes succursales`,
            parBudget.length ? h('ol', { class: 'bf-dash__budget' }, parBudget.map((x) => {
              const e = etatBudget(x); const max = Math.max(x.prevu, x.depense) || 1;
              const li = h('li', {},
                h('span', { class: 'bf-dash__barre-libelle' }, h('span', {}, h('span', { class: 'bf-dash__cle', style: `background:${x.s.couleur}` }), x.s.libelle),
                  h('span', { class: `bf-dash__muet${e === 'depasse' || e === 'hors' ? ' bf-dash__alerte' : ''}` },
                    x.prevu ? `${compact(x.depense)} sur ${compact(x.prevu)} | ${e === 'depasse' ? '⚠ ' : ''}${pctTxt(x.depense / x.prevu)}${e === 'depasse' ? ' (dépassé)' : e === 'sous' ? ' (sous le budget)' : ''}`
                      : `${compact(x.depense)} dépensés | ⚠ aucun budget prévu`)),
                h('span', { class: 'bf-dash__jauge-budget' },
                  h('span', { class: 'bf-dash__jauge-prevu', style: `width:${(x.prevu / max) * 100}%` }),
                  h('span', { class: 'bf-dash__jauge-depense', style: `width:${(x.depense / max) * 100}%;background:${x.s.couleur}` })),
                editionBudget ? h('label', { class: 'bf-dash__saisie' }, h('input', { type: 'number', min: 0, step: 100, value: budget[x.k] || 0, 'aria-label': `Budget mensuel ${x.s.libelle}`,
                  onchange: (ev) => { budget[x.k] = Math.max(0, Math.round(Number(ev.target.value) || 0)); sauverBudget(); setTimeout(rendre, 0); } }), h('span', {}, '$ / mois')) : null);
              survol(li, () => [[compact(x.depense), `dépensés, ${x.s.libelle}`], [compact(x.prevu), 'prévus'], [x.prevu ? pctTxt(x.depense / x.prevu) : 'n/d', 'du budget utilisé']]);
              return li;
            })) : vide('Aucun budget ni dépense.'),
            h('div', { class: 'bf-dash__actions' },
              h('button', { class: 'bf-dash__bouton', type: 'button', onclick: () => { editionBudget = !editionBudget; rendre(); } }, editionBudget ? 'Terminer' : 'Modifier le budget mensuel'),
              editionBudget ? h('button', { class: 'bf-dash__bouton', type: 'button', onclick: () => { budget = { ...BUDGET_DEFAUT }; sauverBudget(); rendre(); } }, 'Remettre le budget de départ') : null),
            h('p', { class: 'bf-dash__muet' }, 'Budget mensuel par source, multiplié par le nombre de mois de la période. Maquette : le budget modifié est gardé dans ce navigateur seulement.')),
          carteGraph('Dépensé et prévu par mois', `12 derniers mois | ${filtres.source ? SOURCES[filtres.source].libelle : 'toutes les sources'}, toutes succursales`,
            ...lignes({ mois: mois12, valeurs: { prevu: budgetMois, depense: depMois }, pasAxe: depMois.some((v) => v > 10000) ? 5000 : 1000, format: (v) => compact(v), enPlein: (m) => P.mois.includes(m),
              series: [{ cle: 'depense', libelle: 'Dépensé', couleur: 'var(--d-m1)' }, { cle: 'prevu', libelle: 'Budget prévu', couleur: '#b6c0d4' }],
              aria: 'Dépenses et budget prévu par mois',
              bulleFin: (i) => [[budgetMois[i] ? pctTxt(depMois[i] / budgetMois[i]) : 'n/d', 'du budget du mois']] }))),

        carteGraph('Performance par source et par campagne', `${P.libelle} | le tableau pour décider où mettre l'argent`,
          h('div', { class: 'bf-dash__defile' }, h('table', { class: 'bf-dash__table bf-dash__vendeurs' },
            h('thead', {}, h('tr', {}, ['Source | campagne', 'Dépenses', 'Clics', 'Leads', 'Coût / lead', 'Visites', 'Ventes', 'Conversion', 'Coût / vente', 'Ventes $', 'Rend. ventes', 'Marge $', 'Rend. marge']
              .map((t, i) => h('th', { class: i ? 'num' : '' }, t)))),
            h('tbody', {}, parSource.flatMap(({ k, s, K: ks }) => {
              const ligne = (libelle, x, classe, couleur) => h('tr', { class: classe },
                h('td', {}, couleur ? h('span', { class: 'bf-dash__cle', style: `background:${couleur}` }) : null, libelle),
                h('td', { class: 'num' }, x.depense ? compact(x.depense) : 'n/a'), h('td', { class: 'num' }, x.clics ? entier(x.clics) : 'n/a'),
                h('td', { class: 'num' }, entier(x.leads)), h('td', { class: 'num' }, x.depense ? nd(x.cpl, dollars) : '0 $'),
                h('td', { class: 'num' }, entier(x.visites)), h('td', { class: 'num' }, entier(x.ventes)), h('td', { class: 'num' }, nd(x.conv, (v) => pctTxt(v, 1))),
                h('td', { class: 'num' }, x.depense ? nd(x.cpv, dollars) : '0 $'), h('td', { class: 'num' }, compact(x.valeur)),
                h('td', { class: 'num' }, rendementTxt(x.rendement)), h('td', { class: 'num' }, compact(x.marge)),
                h('td', { class: `num${x.rendementMarge !== null && x.rendementMarge < 3 ? ' bf-dash__alerte' : ''}` },
                  x.rendementMarge !== null && x.rendementMarge < 3 ? `⚠ ${rendementTxt(x.rendementMarge)}` : rendementTxt(x.rendementMarge)));
              const camps = parCampagne.filter((x) => x.c.source === k);
              return [ligne(s.libelle, ks, 'bf-dash__vendeur', s.couleur), ...(camps.length > 1 ? camps.map(({ c, K: kc }) => ligne(`↳ ${c.nom}`, kc, 'bf-dash__territoire')) : [])];
            })))),
          h('p', { class: 'bf-dash__muet' }, '⚠ = moins de 3 $ de marge brute par 1 $ dépensé. Ventes $ = valeur des ventes conclues à partir de ces leads, avant taxes. Marge $ = marge brute avec installation.')),

        h('div', { class: 'bf-dash__rangee' },
          carteGraph('Du lead à la vente', `${P.libelle} | où on perd les clients`,
            h('ol', { class: 'bf-dash__entonnoir' }, etapes.map(([lib, n], i) => {
              const li = h('li', {}, h('span', { class: 'bf-dash__barre-libelle' }, h('span', {}, lib),
                i ? h('span', { class: 'bf-dash__muet' }, `${pctTxt(etapes[i - 1][1] ? n / etapes[i - 1][1] : 0)} de l'étape d'avant`) : null),
              h('span', { class: 'bf-dash__barre-piste' }, h('span', { class: 'bf-dash__barre', style: `width:${Math.max(1.5, (n / (K.leads || 1)) * 100)}%;background:${SEQ[3 - i] || SEQ[0]}` })),
              h('strong', { class: 'num' }, entier(n)));
              survol(li, () => [[entier(n), lib], [pctTxt(K.leads ? n / K.leads : 0), 'des leads reçus']]);
              return li;
            }))),
          carteGraph('Ce que les gens demandent, par source', `${P.libelle} | leads par type de demande`,
            h('div', { class: 'bf-dash__defile' }, h('table', { class: 'bf-dash__table bf-dash__matrice' },
              h('thead', {}, h('tr', {}, h('th', {}, 'Source'), ...typesVus.map((t) => h('th', { class: 'num' }, TYPES_DEMANDE[t])))),
              h('tbody', {}, parSource.map(({ s }, i) => h('tr', {}, h('td', {}, h('span', { class: 'bf-dash__cle', style: `background:${s.couleur}` }), s.libelle),
                ...matrice[i].map((v) => { const c = celluleSeq(v, maxM); return h('td', { class: `num bf-dash__cellule${c?.claire ? ' bf-dash__cellule--claire' : ''}`, style: c ? `background:${c.fond}` : '' }, v ? entier(v) : ''); })))))))),

        h('div', { class: 'bf-dash__rangee bf-dash__rangee--2-1' },
          carteGraph('D\'où viennent les leads sur la carte', `${P.libelle} | leads par municipalité`, zoneCarte,
            h('div', { class: 'bf-dash__legende bf-dash__legende--seq' }, h('span', {}, 'Moins'),
              ...SEQ.map((c) => h('span', { class: 'bf-dash__cle bf-dash__cle--large', style: `background:${c}` })), h('span', {}, 'Plus'),
              h('span', { class: 'bf-dash__muet' }, `| max ${entier(maxD)} leads`))),
          carteGraph('Secteurs : leads et conversion', `${P.libelle} | par succursale`,
            barres(parSucc.sort((a, b) => b.l.length - a.l.length).map(({ s, l }) => {
              const k = kpi(l, []);
              return { libelle: s.nom, sous: `${pctTxt(k.conv || 0, 1)} achètent | ${compact(k.valeur)} de ventes`, valeur: l.length, texte: entier(l.length),
                bulle: [[pctTxt(k.conv || 0, 1), 'taux de conversion'], [entier(k.ventes), 'ventes']] };
            })))),

        h('div', { class: 'bf-dash__rangee' },
          carteGraph('Qui demande : genre', `${P.libelle} | Facebook, Instagram et Google (rapports agrégés)`,
            parGenre.some((g) => g.leads) ? anneau(parGenre.map((g) => ({ cle: g.k, libelle: g.lib, couleur: COULEUR_GENRE[g.k], n: g.leads })),
              { centre: entier(parGenre.reduce((s, g) => s + g.leads, 0)), unite: 'leads', aria: 'Leads des plateformes par genre' }) : vide('Pas de rapport d\'auditoire pour cette source.'),
            parGenre.some((g) => g.leads) ? h('table', { class: 'bf-dash__table' },
              h('thead', {}, h('tr', {}, h('th', {}, 'Genre'), h('th', { class: 'num' }, 'Coût / lead'), h('th', { class: 'num' }, 'Conversion'))),
              h('tbody', {}, parGenre.filter((g) => g.leads).map((g) => h('tr', {}, h('td', {}, g.lib), h('td', { class: 'num' }, dollars(g.dep / g.leads)), h('td', { class: 'num' }, pctTxt(g.ventes / g.leads, 1)))))) : null),
          carteGraph('Qui demande : âge', `${P.libelle} | leads et conversion par tranche d'âge (rapports agrégés)`,
            parAge.some((a) => a.leads) ? barres(parAge.map((a) => ({ libelle: `${a.age} ans`, sous: a.leads ? `${pctTxt(a.ventes / a.leads, 1)} achètent | ${dollars(a.dep / a.leads)} par lead` : '',
              valeur: a.leads, texte: entier(a.leads), bulle: a.leads ? [[pctTxt(a.ventes / a.leads, 1), 'taux de conversion'], [dollars(a.ventes ? a.dep / a.ventes : 0), 'par vente']] : [] })), { couleur: 'var(--d-s1)' })
              : vide('Pas de rapport d\'auditoire pour cette source.'))),
        h('p', { class: 'bf-dash__muet bf-dash__note' }, 'Loi 25 : le genre et l\'âge ne sont jamais inscrits au dossier d\'un client. Ces chiffres viennent des rapports d\'auditoire que Facebook et Google fournissent en totaux, sans nommer personne.'),

        h('div', { class: 'bf-dash__rangee bf-dash__rangee--2-1' },
          carteGraph('Quand arrivent les leads', `${P.libelle} | par jour et par plage horaire`,
            h('div', { class: 'bf-dash__defile' }, h('table', { class: 'bf-dash__table bf-dash__matrice bf-dash__chaleur' },
              h('thead', {}, h('tr', {}, h('th', {}, ''), ...PLAGES.map(([, , lib]) => h('th', { class: 'num' }, lib)))),
              h('tbody', {}, JOURS_SEMAINE.map((j, i) => h('tr', {}, h('td', {}, j), ...grille[i].map((v, k) => {
                const c = celluleSeq(v, maxG);
                const td = h('td', { class: `num bf-dash__cellule${c?.claire ? ' bf-dash__cellule--claire' : ''}`, style: c ? `background:${c.fond}` : '' }, v ? entier(v) : '');
                survol(td, () => [[`${entier(v)} leads`, `${j} ${PLAGES[k][2]}`]]);
                return td;
              }))))))),
          carteGraph('Pistes pour le budget', 'Calculées à partir des chiffres affichés | à valider avec ton agence', h('ul', { class: 'bf-dash__pistes' }, pistes()))));

      function pistes() {
        const liste = [];
        const payees = parCampagne.filter((x) => x.K.depense > 0 && x.K.leads >= 10 && x.c.cpc > 0);   // publicités Facebook, Google, Instagram
        if (payees.length) {
          const meilleure = [...payees].sort((a, b) => b.K.rendementMarge - a.K.rendementMarge)[0];
          const pire = [...payees].sort((a, b) => a.K.rendementMarge - b.K.rendementMarge)[0];
          liste.push(`Augmenter : « ${meilleure.c.nom} » rapporte ${rendementTxt(meilleure.K.rendementMarge)} de marge par 1 $ (${nd(meilleure.K.cpv, dollars)} par vente).`);
          if (pire !== meilleure && pire.K.rendementMarge < 5) liste.push(`Réduire ou revoir : « ${pire.c.nom} » ne rapporte que ${rendementTxt(pire.K.rendementMarge)} de marge par 1 $ ; ses leads achètent ${pctTxt(pire.K.conv || 0, 1)} du temps et obtiennent plus de rabais.`);
          const moinsCher = [...payees].sort((a, b) => a.K.cpl - b.K.cpl)[0];
          if (moinsCher !== meilleure) liste.push(`Attention au coût par lead : « ${moinsCher.c.nom} » a les leads les moins chers (${dollars(moinsCher.K.cpl)}), mais ce n'est pas la plus rentable. Juger au coût par vente, pas au coût par lead.`);
        }
        const web = parCampagne.find((x) => x.c.code === 'web-seo');
        if (web && web.K.rendementMarge && payees.length && web.K.rendementMarge > Math.max(...payees.map((x) => x.K.rendementMarge))) {
          liste.push(`Le site web rapporte ${rendementTxt(web.K.rendementMarge)} de marge par 1 $ investi dans le référencement et le contenu, mieux que toute publicité. Ses volumes sont petits (${entier(web.K.leads)} leads) : investir dans le contenu à long terme.`);
        }
        // Budget : dépassements et budget non utilisé sur une source rentable
        for (const x of parBudget) {
          const e = etatBudget(x); const k = parSource.find((p) => p.k === x.k)?.K;
          if (e === 'depasse') liste.push(`Budget dépassé : ${x.s.libelle} a dépensé ${pctTxt(x.depense / x.prevu)} du budget prévu (${compact(x.depense - x.prevu)} de plus).`);
          if (e === 'sous' && k?.rendementMarge > 8) liste.push(`Budget non utilisé : ${x.s.libelle} a ${compact(x.prevu - x.depense)} de budget restant et rapporte ${rendementTxt(k.rendementMarge)} de marge par 1 $. Le dépenser vaut probablement la peine.`);
        }
        const secteurs = parSucc.map(({ s, l }) => ({ s, k: kpi(l, []) })).filter((x) => x.k.leads >= 20);
        if (secteurs.length > 1) {
          const conv = [...secteurs].sort((a, b) => b.k.conv - a.k.conv)[0];
          const moyenne = secteurs.reduce((s, x) => s + x.k.leads, 0) / secteurs.length;
          if (conv.k.leads < moyenne) liste.push(`Secteur à pousser : ${conv.s.nom} convertit le mieux (${pctTxt(conv.k.conv, 1)}) avec moins de leads que la moyenne. Cibler davantage ce secteur.`);
          else liste.push(`Secteur le plus payant : ${conv.s.nom} (${pctTxt(conv.k.conv, 1)} des leads achètent).`);
        }
        const ages = parAge.filter((a) => a.leads >= 15).map((a) => ({ ...a, cpv: a.ventes ? a.dep / a.ventes : Infinity }));
        if (ages.length) {
          const best = [...ages].sort((a, b) => a.cpv - b.cpv)[0]; const worst = [...ages].sort((a, b) => b.cpv - a.cpv)[0];
          liste.push(`Cible : les ${best.age} ans coûtent le moins cher par vente (${dollars(best.cpv)}) ; les ${worst.age} ans, le plus (${worst.cpv === Infinity ? 'aucune vente' : dollars(worst.cpv)}). Ajuster le ciblage par âge dans Facebook et Google.`);
        }
        const plat = grille.flat(); const iMax = plat.indexOf(Math.max(...plat));
        if (plat[iMax]) liste.push(`Horaire : le plus de leads arrive le ${JOURS_LONGS[Math.floor(iMax / PLAGES.length)]} de ${PLAGES[iMax % PLAGES.length][2]}. Concentrer la diffusion des pubs juste avant, et avoir un vendeur disponible pour rappeler vite.`);
        const ref = parSource.find((x) => x.k === 'reference');
        if (ref && ref.K.conv) liste.push(`Les références convertissent à ${pctTxt(ref.K.conv, 1)} sans coût : un programme de référence (prime au client qui recommande) est souvent le meilleur placement.`);
        return liste.length ? liste.map((t) => h('li', {}, t)) : [h('li', {}, 'Pas assez de données dans ce filtre.')];
      }

      if (geo) {
        if (!carte) {
          carte = creerCarte(zoneCarte, geo, {
            reperes, vueDepart: { ouest: -76.3, sud: 45.25, est: -71.6, nord: 46.35 },
            couleur: (code) => { const n = densite.get(code); return n ? SEQ[classe(n)] : 'var(--d-vide)'; },
            titre: (f) => f.properties.nom,
            onClic: (f, e) => montrerBulle(e, [[`${densite.get(f.properties.code) || 0} leads`, f.properties.nom]]),
          });
        }
        carte.redessiner();
      } else remplir(zoneCarte, vide('Carte non disponible (limites municipales absentes).'));
    }
    rendre();
    let etroitAvant = window.innerWidth < 640;
    window.addEventListener('resize', () => { const e = window.innerWidth < 640; if (e !== etroitAvant) { etroitAvant = e; rendre(); } });
  }
}
