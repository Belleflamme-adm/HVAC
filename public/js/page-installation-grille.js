// Grille d'installation | listes de prix des sous-traitants (ADR-060), au style de la liste de prix de Mike :
// une ligne par travail (code | nom), ce qui est inclus, le prix client calculé, et le coût du sous-traitant au bout.
// Lecture : rôles commerciaux. Écriture : Simon et Mike (RLS). Un prix ne se modifie pas : chaque
// enregistrement ajoute un tarif daté (l'historique reste).
import { initPage } from './bf-page.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message, dateFr, pct, param } from './bf-dom.js?v=0.4.0';
import { formatCents } from './bf-money.js?v=0.4.0';

const UNITES = { forfait: 'forfait', tete: 'par tête', pied: 'par pied', sortie: 'par sortie', heure: 'par heure', unite: 'par unité', livre: 'par livre' };

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const admin = user.role === 'Admin tout' || user.role === 'Direction';
  const enCents = (t) => {
    const n = Number(String(t).replace(',', '.').replace(/[\s$]/g, ''));
    return Number.isFinite(n) && n > 0 ? Math.round(n * 100) : null;
  };
  let fournisseur = param('fournisseur') || '';
  let filtre = '';

  async function charger() {
    let o;
    try { o = await api.get('installation-options'); } catch (e) { remplir(zone, msg); message(msg, e.message); return; }
    const { types, categories = [], sousTraitants, grille, margeBp } = o;
    if (!fournisseur && sousTraitants.length) fournisseur = sousTraitants[0].id;
    const prixClient = (c) => Math.round(c * 10000 / (10000 - margeBp));
    const tarif = (typeId) => grille.find((g) => g.fournisseur_id === fournisseur && g.type_travail_id === typeId);

    // Marge (Simon et Mike)
    const champMarge = h('input', { id: 'marge', inputmode: 'decimal', value: String(margeBp / 100).replace('.', ','), class: 'bf-court', 'aria-label': 'Marge en %' });
    const formMarge = h('form', { class: 'bf-filtres' }, 'Marge sur le prix de vente :', champMarge, ' %',
      h('button', { class: 'bf-bouton bf-bouton--discret', type: 'submit' }, 'Enregistrer la marge'));
    formMarge.addEventListener('submit', async (ev) => {
      ev.preventDefault();
      const bp = Math.round(Number(champMarge.value.replace(',', '.')) * 100);
      try { await api.patch('installation-tarifs', { marge_bp: bp }); message(msg, `Marge enregistrée : ${pct(bp)} (nouvelles lignes d'installation seulement).`, 'ok'); charger(); }
      catch (e) { message(msg, e.message); }
    });

    // Choix du sous-traitant et recherche
    const choixSt = h('select', { id: 'sous-traitant', 'aria-label': 'Sous-traitant' },
      sousTraitants.map((f) => h('option', { value: f.id, selected: f.id === fournisseur }, f.nom)));
    choixSt.addEventListener('change', () => { fournisseur = choixSt.value; charger(); });
    const recherche = h('input', { id: 'recherche-travail', type: 'search', placeholder: 'Chercher un travail (ex. multizone, biénergie, EXTRA)…', value: filtre, 'aria-label': 'Chercher un travail' });

    // Lignes de prix, groupées par catégorie
    const modifies = new Map();   // type_travail_id -> cents
    const bouton = h('button', { class: 'bf-bouton', type: 'button', disabled: true }, 'Enregistrer les prix');
    const majBouton = () => { bouton.disabled = !modifies.size; bouton.textContent = modifies.size ? `Enregistrer les prix (${modifies.size})` : 'Enregistrer les prix'; };
    const lignes = [];
    const ligne = (t) => {
      const actuel = tarif(t.id);
      const client = h('span', { class: 'bf-prix__client' }, actuel ? `Prix client : ${formatCents(prixClient(actuel.cout_cents))}` : 'Prix client : à venir');
      const champ = h('input', { class: 'bf-prix__champ', inputmode: 'decimal', placeholder: 'Coût', disabled: !admin || !fournisseur,
        value: actuel ? String(actuel.cout_cents / 100).replace('.', ',') : '', 'aria-label': `Coût du sous-traitant : ${t.nom}` });
      champ.addEventListener('input', () => {
        const c = enCents(champ.value);
        if (c && c !== actuel?.cout_cents) modifies.set(t.id, c); else modifies.delete(t.id);
        client.textContent = c ? `Prix client : ${formatCents(prixClient(c))}` : (actuel ? `Prix client : ${formatCents(prixClient(actuel.cout_cents))}` : 'Prix client : à venir');
        champ.classList.toggle('bf-prix__champ--modifie', modifies.has(t.id));
        majBouton();
      });
      const el = h('div', { class: 'bf-prix' },
        h('div', { class: 'bf-prix__texte' },
          h('div', {}, h('strong', {}, t.code), ` | ${t.nom}`),
          t.description ? h('div', { class: 'bf-prix__inclus' }, t.description) : null,
          h('div', { class: 'bf-prix__meta' }, client, actuel ? h('span', { class: 'bf-muet' }, ` · en vigueur depuis le ${dateFr(actuel.en_vigueur_du)}`) : null)),
        h('label', { class: 'bf-prix__saisie' }, champ, h('span', { class: 'bf-prix__unite' }, UNITES[t.unite] || t.unite || 'forfait')));
      lignes.push({ el, t });
      return el;
    };
    const parCat = new Map(categories.map((c) => [c.code, []]));
    parCat.set(null, []);
    for (const t of types) (parCat.has(t.categorie) ? parCat.get(t.categorie) : parCat.get(null)).push(t);
    const sections = [...parCat.entries()].filter(([, ts]) => ts.length).map(([code, ts]) => {
      const nom = categories.find((c) => c.code === code)?.nom || 'Autres';
      const sec = h('section', { class: 'bf-prix-section' }, h('h2', { class: 'bf-prix-section__titre' }, `HVAC | ${nom}`), ts.map(ligne));
      return { sec, ts };
    });
    const appliquerFiltre = () => {
      const q = recherche.value.trim().toLowerCase();
      filtre = recherche.value;
      for (const { el, t } of lignes) el.hidden = Boolean(q) && ![t.code, t.nom, t.description].some((v) => String(v || '').toLowerCase().includes(q));
      for (const { sec } of sections) sec.hidden = [...sec.querySelectorAll('.bf-prix')].every((x) => x.hidden);
    };
    recherche.addEventListener('input', appliquerFiltre);

    bouton.addEventListener('click', async () => {
      const aujourdhui = new Date().toISOString().slice(0, 10);
      try {
        for (const [typeId, cents] of modifies) {
          await api.post('installation-tarifs', { fournisseur_id: fournisseur, type_travail_id: typeId, cout_cents: cents, en_vigueur_du: aujourdhui });
        }
        message(msg, `${modifies.size} prix enregistré(s), en vigueur aujourd'hui. Les anciens prix restent dans l'historique.`, 'ok');
        charger();
      } catch (e) { message(msg, e.message); }
    });

    // Nouveau type de travail (Simon et Mike)
    const code = h('input', { id: 'nouveau-code', placeholder: 'Code (ex. INST-MURAL-1T-30)', required: true, class: 'bf-court' });
    const nom = h('input', { id: 'nouveau-nom', placeholder: 'Nom du travail', required: true });
    const cat = h('select', { id: 'nouveau-cat', 'aria-label': 'Catégorie' }, categories.map((c) => h('option', { value: c.code }, c.nom)));
    const unite = h('select', { id: 'nouveau-unite', 'aria-label': 'Unité' }, Object.entries(UNITES).map(([v, l]) => h('option', { value: v }, l)));
    const formType = h('form', { class: 'bf-filtres' }, code, nom, cat, unite, h('button', { class: 'bf-bouton bf-bouton--discret', type: 'submit' }, 'Ajouter le travail'));
    formType.addEventListener('submit', async (ev) => {
      ev.preventDefault();
      try { await api.put('installation-tarifs', { code: code.value, nom: nom.value.trim(), categorie: cat.value, unite: unite.value }); message(msg, 'Travail ajouté à la liste.', 'ok'); charger(); }
      catch (e) { message(msg, e.message); }
    });

    const remplis = types.filter((t) => tarif(t.id)).length;
    remplir(zone,
      h('h1', {}, 'Listes de prix des sous-traitants'),
      h('p', { class: 'bf-muet' }, `Le sous-traitant donne son coût pour chaque travail. Prix client = coût / (1 - marge). Marge actuelle : ${pct(margeBp)}.`),
      msg,
      admin ? h('section', { class: 'bf-carte-section' }, formMarge) : null,
      h('div', { class: 'bf-filtres' }, h('strong', {}, 'Sous-traitant'), choixSt,
        h('span', { class: 'bf-muet' }, `${remplis} prix sur ${types.length} travaux`)),
      recherche,
      sections.map((s) => s.sec),
      admin ? h('div', { class: 'bf-prix-barre' }, bouton, h('span', { class: 'bf-muet' }, 'Un prix enregistré prend effet aujourd\'hui ; l\'ancien reste dans l\'historique.')) : null,
      admin ? h('section', { class: 'bf-carte-section' }, h('h2', {}, 'Ajouter un travail à la liste'), formType) : null);
    appliquerFiltre();
  }
  charger();
}
