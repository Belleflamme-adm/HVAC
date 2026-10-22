// Grille des sous-traitants et taux de marge. Lecture : rôles commerciaux. Écriture : Simon et Mike (RLS).
import { initPage } from './bf-page.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message, dateFr, pct } from './bf-dom.js?v=0.4.0';
import { formatCents } from './bf-money.js?v=0.4.0';

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const admin = user.role === 'Admin tout' || user.role === 'Direction';
  const enCents = (t) => Math.round(Number(String(t).replace(',', '.').replace(/\s/g, '')) * 100);

  async function charger() {
    let o;
    try { o = await api.get('installation-options'); } catch (e) { remplir(zone, msg); message(msg, e.message); return; }
    const { types, sousTraitants, grille, margeBp } = o;
    const prix = (c) => Math.round(c * 10000 / (10000 - margeBp));
    const action = async (fn, ok) => { try { await fn(); message(msg, ok, 'ok'); charger(); } catch (e) { message(msg, e.message); } };

    const champMarge = h('input', { inputmode: 'decimal', value: String(margeBp / 100).replace('.', ','), class: 'bf-court', 'aria-label': 'Marge en %' });
    const formMarge = h('form', { class: 'bf-filtres' }, 'Marge sur le prix de vente :', champMarge, ' %',
      h('button', { class: 'bf-bouton bf-bouton--discret', type: 'submit' }, 'Enregistrer'));
    formMarge.addEventListener('submit', (ev) => {
      ev.preventDefault();
      const bp = Math.round(Number(champMarge.value.replace(',', '.')) * 100);
      if (!confirm(`Nouvelle marge : ${pct(bp)}. Elle s'applique aux NOUVELLES lignes d'installation seulement. Continuer ?`)) return;
      action(() => api.patch('installation-tarifs', { marge_bp: bp }), 'Marge enregistrée.');
    });

    const selSt = h('select', { required: true, 'aria-label': 'Sous-traitant' }, h('option', { value: '' }, 'Sous-traitant…'), sousTraitants.map((f) => h('option', { value: f.id }, f.nom)));
    const selType = h('select', { required: true, 'aria-label': 'Type de travail' }, h('option', { value: '' }, 'Type de travail…'), types.map((t) => h('option', { value: t.id }, t.nom)));
    const cout = h('input', { inputmode: 'decimal', placeholder: 'Coût $', required: true, class: 'bf-court', 'aria-label': 'Coût' });
    const date = h('input', { type: 'date', value: new Date().toISOString().slice(0, 10), 'aria-label': 'En vigueur le' });
    const formTarif = h('form', { class: 'bf-filtres' }, selSt, selType, cout, date, h('button', { class: 'bf-bouton bf-bouton--discret', type: 'submit' }, 'Ajouter le tarif'));
    formTarif.addEventListener('submit', (ev) => {
      ev.preventDefault();
      action(() => api.post('installation-tarifs', { fournisseur_id: selSt.value, type_travail_id: selType.value, cout_cents: enCents(cout.value), en_vigueur_du: date.value }), 'Tarif ajouté.');
    });

    const code = h('input', { placeholder: 'Code (ex. INST-MUR)', required: true, class: 'bf-court' });
    const nom = h('input', { placeholder: 'Nom du type de travail', required: true });
    const formType = h('form', { class: 'bf-filtres' }, code, nom, h('button', { class: 'bf-bouton bf-bouton--discret', type: 'submit' }, 'Ajouter le type'));
    formType.addEventListener('submit', (ev) => { ev.preventDefault(); action(() => api.put('installation-tarifs', { code: code.value.trim().toUpperCase(), nom: nom.value.trim() }), 'Type ajouté.'); });

    const nomSt = Object.fromEntries(sousTraitants.map((f) => [f.id, f.nom]));
    const nomType = Object.fromEntries(types.map((t) => [t.id, t.nom]));
    remplir(zone,
      h('h1', {}, 'Grille d\'installation'),
      h('p', { class: 'bf-muet' }, `Prix client = coût du sous-traitant / (1 - marge). Marge actuelle : ${pct(margeBp)}. Exemple : un coût de 1 000 $ donne ${formatCents(prix(100000))}.`),
      msg,
      admin ? h('section', { class: 'bf-carte-section' }, h('h2', {}, 'Marge'), formMarge) : null,
      h('div', { class: 'bf-table-zone' }, h('table', { class: 'bf-table' },
        h('thead', {}, h('tr', {}, ['Sous-traitant', 'Type de travail', 'Coût', 'Prix client', 'En vigueur depuis'].map((t) => h('th', {}, t)))),
        h('tbody', {}, grille.length ? grille.map((g) => h('tr', {},
          h('td', {}, nomSt[g.fournisseur_id] || ''), h('td', {}, nomType[g.type_travail_id] || ''),
          h('td', { class: 'num' }, formatCents(g.cout_cents)), h('td', { class: 'num' }, formatCents(prix(g.cout_cents))), h('td', {}, dateFr(g.en_vigueur_du))))
          : h('tr', {}, h('td', { colspan: 5, class: 'bf-muet' }, 'Aucun tarif.'))))),
      admin ? h('section', { class: 'bf-carte-section' }, h('h2', {}, 'Nouveau tarif'),
        h('p', { class: 'bf-muet' }, 'Un tarif ne se modifie pas : un nouveau tarif daté remplace l\'ancien à partir de sa date. L\'historique est conservé.'), formTarif) : null,
      admin ? h('section', { class: 'bf-carte-section' }, h('h2', {}, 'Nouveau type de travail'), formType) : null);
  }
  charger();
}
