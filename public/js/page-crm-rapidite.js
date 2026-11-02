// Rapidité des vendeurs (ADR-056) : tableau de quantification (seuils bon / moyen saisis par Simon et Mike)
// et comparaison avec les chiffres réels de chaque vendeur. Gestion des vendeurs du board (tour de rôle).
import { initPage } from './bf-page.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message } from './bf-dom.js?v=0.4.0';
import { pastilleCote, duree, voitBoard, TYPES_DEMANDE } from './bf-crm.js?v=0.4.0';

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const modifiable = voitBoard(user);
  const unite = (o) => (o.unite === 'minutes' ? 'min' : '%');
  const valeur = (o, v) => (v === null || v === undefined ? 'n/d' : o.unite === 'minutes' ? duree(v) : `${Number(v).toLocaleString('fr-CA')} %`);

  async function charger() {
    let d;
    try { d = await api.get('crm-rapidite'); } catch (e) { remplir(zone, h('h1', {}, 'Rapidité des vendeurs'), h('p', { class: 'bf-message' }, e.message)); return; }
    const { objectifs, vendeurs, evaluation } = d;
    const cote = (emp, ind) => evaluation.find((e) => e.employe_id === emp && e.indicateur === ind)?.cote || 'non_evalue';

    // 1. Tableau de quantification
    const champs = new Map();
    const tableauObjectifs = h('div', { class: 'bf-table-zone' }, h('table', { class: 'bf-table' },
      h('thead', {}, h('tr', {}, h('th', {}, 'Indicateur'), h('th', {}, 'Bon si'), h('th', {}, 'Moyen si'), h('th', {}, 'Sinon'))),
      h('tbody', {}, objectifs.map((o) => {
        const signe = o.sens === 'bas' ? '≤' : '≥';
        const entree = (k) => {
          const el = h('input', { type: 'number', min: 0, step: 'any', value: o[k] ?? '', disabled: !modifiable, 'aria-label': `${o.libelle} ${k}`, class: 'bf-seuil' });
          champs.set(`${o.indicateur}:${k}`, el);
          return el;
        };
        return h('tr', {}, h('td', {}, o.libelle),
          h('td', {}, `${signe} `, entree('seuil_bon'), ` ${unite(o)}`),
          h('td', {}, `${signe} `, entree('seuil_moyen'), ` ${unite(o)}`),
          h('td', {}, 'À améliorer'));
      }))));
    const enregistrer = modifiable ? h('button', { class: 'bf-bouton', type: 'button', onclick: async () => {
      const lignes = objectifs.map((o) => ({ indicateur: o.indicateur,
        seuil_bon: champs.get(`${o.indicateur}:seuil_bon`).value, seuil_moyen: champs.get(`${o.indicateur}:seuil_moyen`).value }));
      try { await api.put('crm-rapidite', { objectifs: lignes }); await charger(); message(msg, 'Tableau de quantification enregistré.', 'ok'); }
      catch (e) { message(msg, e.message); }
    } }, 'Enregistrer les seuils') : null;

    // 2. Vendeurs comparés au tableau
    const tableauVendeurs = vendeurs.length ? h('div', { class: 'bf-table-zone' }, h('table', { class: 'bf-table' },
      h('thead', {}, h('tr', {}, h('th', {}, 'Vendeur'), h('th', {}, 'Leads'), objectifs.map((o) => h('th', {}, o.libelle)))),
      h('tbody', {}, vendeurs.map((v) => h('tr', {},
        h('td', {}, h('strong', {}, v.vendeur_nom)),
        h('td', { class: 'num' }, String(v.leads)),
        objectifs.map((o) => h('td', {}, h('div', {}, valeur(o, v[o.indicateur])), pastilleCote(cote(v.employe_id, o.indicateur)))))))))
      : h('p', { class: 'bf-muet' }, 'Aucun lead attribué pour l\'instant.');

    // 3. Vendeurs du board (tour de rôle)
    let board = null;
    if (modifiable) {
      const { membres, employes } = await api.get('crm-vendeurs').catch(() => ({ membres: [], employes: [] }));
      const parId = new Map(membres.map((m) => [m.employe_id, m]));
      const cases = employes.map((e) => {
        const m = parId.get(e.id);
        const actif = h('input', { type: 'checkbox', checked: Boolean(m?.actif) });
        const ordre = h('input', { type: 'number', min: 1, value: m?.ordre ?? '', class: 'bf-seuil', 'aria-label': 'Ordre' });
        // Nouveau vendeur : qualifié pour tout par défaut ; on décoche ce qu'il ne doit pas prendre
        const types = Object.fromEntries(Object.keys(TYPES_DEMANDE).map((t) => [t,
          h('input', { type: 'checkbox', checked: m ? (m.types || []).includes(t) : true, 'aria-label': `${e.prenom} ${e.nom} : ${TYPES_DEMANDE[t]}` })]));
        return { e, actif, ordre, types, ligne: h('tr', {}, h('td', {}, `${e.prenom} ${e.nom}`), h('td', {}, actif), h('td', {}, ordre),
          Object.values(types).map((c) => h('td', { class: 'bf-centre-cel' }, c))) };
      });
      board = h('section', { class: 'bf-carte-section' },
        h('h2', {}, 'Vendeurs du board et types de demande'),
        h('p', { class: 'bf-muet' }, 'Un lead va à tour de rôle aux vendeurs du board qualifiés pour son type, dans l\'ordre indiqué. Si aucun vendeur n\'est qualifié, le lead reste non attribué et tu choisis toi-même. Un lead dont le type est à préciser va à tous les vendeurs du board.'),
        h('div', { class: 'bf-table-zone' }, h('table', { class: 'bf-table' },
          h('thead', {}, h('tr', {}, h('th', {}, 'Vendeur'), h('th', {}, 'Dans le board'), h('th', {}, 'Ordre'),
            Object.values(TYPES_DEMANDE).map((t) => h('th', { class: 'bf-centre-cel' }, t)))),
          h('tbody', {}, cases.map((c) => c.ligne)))),
        h('button', { class: 'bf-bouton', type: 'button', onclick: async () => {
          const vendeurs = cases.filter((c) => c.actif.checked || parId.has(c.e.id)).map((c, i) => ({
            employe_id: c.e.id, actif: c.actif.checked, ordre: Number(c.ordre.value) || i + 1,
            types: Object.entries(c.types).filter(([, el]) => el.checked).map(([t]) => t) }));
          try { await api.put('crm-vendeurs', { vendeurs }); await charger(); message(msg, 'Vendeurs du board enregistrés.', 'ok'); }
          catch (e) { message(msg, e.message); }
        } }, 'Enregistrer les vendeurs'));
    }

    remplir(zone,
      h('p', {}, h('a', { href: '/leads' }, '← Leads')),
      h('h1', {}, 'Rapidité des vendeurs'), msg,
      h('section', { class: 'bf-carte-section' },
        h('h2', {}, 'Tableau de quantification'),
        h('p', { class: 'bf-muet' }, 'Ce qu\'on attend d\'un vendeur. Laisse vide tant que ce n\'est pas décidé : le vendeur reste « non évalué ». Délais en minutes, du moment où le lead arrive.'),
        tableauObjectifs, enregistrer),
      h('section', { class: 'bf-carte-section' }, h('h2', {}, 'Résultats par vendeur'),
        h('p', { class: 'bf-muet' }, 'Délais : médiane de tous les leads du vendeur. Pourcentages : sur tous ses leads.'), tableauVendeurs),
      board);
  }
  charger();
}
