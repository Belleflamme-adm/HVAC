// Grille d'installation | listes de prix des sous-traitants (ADR-060), au style de la liste de prix de Mike :
// une ligne par travail (code | nom), ce qui est inclus, le prix client calculé, et le coût du sous-traitant au bout.
// Lecture : rôles commerciaux. Écriture : Simon et Mike (RLS). Un prix ne se modifie pas : chaque
// enregistrement ajoute un tarif daté (l'historique reste).
import { initPage } from './bf-page.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message, dateFr, pct, param } from './bf-dom.js?v=0.4.0';
import { formatCents } from './bf-money.js?v=0.4.0';

// ADR-062 : la demande de prix par lien (ADR-061) est en veille ; les cases servent à choisir les travaux confiés.
const DEMANDES_PAR_LIEN = false;
const UNITES = { forfait: 'forfait', tete: 'par tête', pied: 'par pied', sortie: 'par sortie', heure: 'par heure', unite: 'par unité', livre: 'par livre' };

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const admin = user.role === 'Admin tout' || user.role === 'Direction';
  const peutDemander = admin || user.role === 'Coordonnateur';
  const enCents = (t) => {
    const n = Number(String(t).replace(',', '.').replace(/[\s$]/g, ''));
    return Number.isFinite(n) && n > 0 ? Math.round(n * 100) : null;
  };
  let fournisseur = param('fournisseur') || '';
  let filtre = '';
  const choisis = new Set();   // travaux cochés pour une demande de prix
  let lienCree = null;         // dernier lien créé : affiché une seule fois, après le rechargement

  async function charger() {
    let o;
    try { o = await api.get('installation-options'); } catch (e) { remplir(zone, msg); message(msg, e.message); return; }
    const { types, categories = [], sousTraitants, grille, margeBp, confies = [] } = o;
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
    choixSt.addEventListener('change', () => { fournisseur = choixSt.value; choisis.clear(); lienCree = null; charger(); });
    const recherche = h('input', { id: 'recherche-travail', type: 'search', placeholder: 'Chercher un travail (ex. multizone, biénergie, EXTRA)…', value: filtre, 'aria-label': 'Chercher un travail' });

    // Travaux confiés à ce sous-traitant (cases) : ce sont les lignes qu'il voit et prix dans son portail
    const confiesSt = new Set(confies.filter((c) => c.fournisseur_id === fournisseur).map((c) => c.type_travail_id));
    if (!DEMANDES_PAR_LIEN) { choisis.clear(); confiesSt.forEach((id) => choisis.add(id)); }
    const boutonConfies = h('button', { class: 'bf-bouton', type: 'button', disabled: true }, 'Enregistrer les travaux confiés');
    const majConfies = () => {
      const ajouter = [...choisis].filter((id) => !confiesSt.has(id));
      const retirer = [...confiesSt].filter((id) => !choisis.has(id));
      boutonConfies.disabled = !(ajouter.length + retirer.length) || !fournisseur;
      boutonConfies.textContent = ajouter.length + retirer.length ? `Enregistrer les travaux confiés (+${ajouter.length} | -${retirer.length})` : `${choisis.size} travaux confiés`;
      return { ajouter, retirer };
    };
    boutonConfies.addEventListener('click', async () => {
      const { ajouter, retirer } = majConfies();
      try { await api.post('travaux-confies', { fournisseur_id: fournisseur, ajouter, retirer }); message(msg, 'Travaux confiés enregistrés : le sous-traitant les voit dans « Ma liste de prix ».', 'ok'); charger(); }
      catch (e) { message(msg, e.message); }
    });

    // Demande de prix : travaux cochés pour le sous-traitant choisi
    const boutonDemande = h('button', { class: 'bf-bouton', type: 'button', disabled: true }, 'Créer la demande de prix');
    const messageDemande = h('input', { id: 'message-demande', placeholder: 'Message au sous-traitant (optionnel)', 'aria-label': 'Message au sous-traitant' });
    const resultatLien = h('div');
    const majDemande = () => {
      if (!DEMANDES_PAR_LIEN) { majConfies(); return; }
      boutonDemande.disabled = !choisis.size || !fournisseur;
      boutonDemande.textContent = choisis.size ? `Créer la demande de prix (${choisis.size} travaux)` : 'Coche les travaux à demander';
    };
    boutonDemande.addEventListener('click', async () => {
      try {
        const d = await api.post('prix-demandes', { fournisseur_id: fournisseur, types: [...choisis], message: messageDemande.value.trim() || undefined });
        lienCree = { d, nomSt: sousTraitants.find((f) => f.id === fournisseur)?.nom || '' };
        choisis.clear();
        await charger();
      } catch (e) { message(msg, e.message); }
    });
    function afficherLien(d, nomSt) {
      const champLien = h('input', { readonly: true, value: d.lien, 'aria-label': 'Lien à envoyer', class: 'bf-lien-demande' });
      const sujet = encodeURIComponent('Belleflamme | Ta liste de prix à remplir');
      const corps = encodeURIComponent(`Bonjour,\n\nVoici la liste de prix à remplir pour Belleflamme :\n${d.lien}\n\nLe lien est valide jusqu'au ${dateFr(d.expire_le)} et ne sert qu'une fois. Merci de signer à la fin.\n\nSimon Cardinal`);
      const copie = h('button', { class: 'bf-bouton', type: 'button', onclick: async () => {
        try { await navigator.clipboard.writeText(d.lien); copie.textContent = 'Lien copié'; } catch { champLien.select(); copie.textContent = 'Sélectionné : Ctrl+C'; }
      } }, 'Copier le lien');
      remplir(resultatLien, h('section', { class: 'bf-carte-section bf-demande-ok' },
        h('h2', {}, `Demande créée pour ${nomSt}`),
        h('p', {}, 'Envoie ce lien au sous-traitant. Il le remplit, signe, et ses prix arrivent ici pour ton approbation. ',
          h('strong', {}, 'Le lien n\'est affiché qu\'une seule fois'), ' : copie-le maintenant.'),
        champLien,
        h('div', { class: 'bf-actions' }, copie,
          h('a', { class: 'bf-bouton bf-bouton--discret', href: `mailto:?subject=${sujet}&body=${corps}` }, 'Envoyer par courriel'),
          h('a', { class: 'bf-bouton bf-bouton--discret', href: `sms:?&body=${corps}` }, 'Envoyer par texto')),
        h('p', { class: 'bf-muet' }, `Valide jusqu'au ${dateFr(d.expire_le)}. Les prix signés seront valides un an à partir de la date de signature.`)));
      resultatLien.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }

    // Demandes déjà envoyées à ce sous-traitant
    let demandes = [];
    try { demandes = DEMANDES_PAR_LIEN && peutDemander && fournisseur ? await api.get('prix-demandes', { fournisseur }) : []; } catch { demandes = []; }
    const STATUTS_DEMANDE = { envoyee: 'Envoyée, en attente', recue: 'Reçue : à approuver', approuvee: 'Approuvée', annulee: 'Annulée' };
    const listeDemandes = demandes.length ? h('div', { class: 'bf-liste' }, demandes.map((d) => h('a', { class: 'bf-ligne', href: `/demande-prix?id=${d.id}` },
      h('strong', {}, `Demande du ${dateFr(d.created_at)}`),
      h('span', { class: `bf-pastille bf-pastille--demande-${d.statut}` }, STATUTS_DEMANDE[d.statut] || d.statut),
      d.signe_le ? h('span', { class: 'bf-muet' }, `signée par ${d.signataire_nom} le ${dateFr(d.signe_le)}, valide jusqu'au ${dateFr(d.valide_jusqu)}`)
        : h('span', { class: 'bf-muet' }, d.ouverte_le ? `ouverte le ${dateFr(d.ouverte_le)}` : 'pas encore ouverte')))) : h('p', { class: 'bf-muet' }, 'Aucune demande envoyée à ce sous-traitant.');

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
      const coche = h('input', { type: 'checkbox', class: 'bf-prix__coche', checked: choisis.has(t.id), 'aria-label': `${DEMANDES_PAR_LIEN ? 'Demander le prix' : 'Confié à ce sous-traitant'} : ${t.nom}` });
      coche.addEventListener('change', () => { if (coche.checked) choisis.add(t.id); else choisis.delete(t.id); majDemande(); });
      const texte = h('div', { class: 'bf-prix__texte' },
        h('div', {}, h('strong', {}, t.code), ` | ${t.nom}`),
        t.description ? h('div', { class: 'bf-prix__inclus' }, t.description) : null,
        h('div', { class: 'bf-prix__meta' }, client,
          actuel ? h('span', { class: 'bf-muet' }, ` · en vigueur depuis le ${dateFr(actuel.en_vigueur_du)}`) : null,
          actuel?.valide_jusqu ? h('span', { class: actuel.valide_jusqu < new Date().toISOString().slice(0, 10) ? 'bf-retard' : 'bf-muet' }, ` · valide jusqu'au ${dateFr(actuel.valide_jusqu)}`) : null));
      // Édition de la ligne (Simon et Mike) : titre, description, unité
      const modifier = admin ? h('button', { class: 'bf-lien', type: 'button', onclick: () => {
        const nom = h('input', { value: t.nom, 'aria-label': 'Titre', class: 'bf-prix__edit' });
        const desc = h('textarea', { rows: 2, 'aria-label': 'Description', class: 'bf-prix__edit' }, t.description || '');
        const un = h('select', { 'aria-label': 'Unité' }, Object.entries(UNITES).map(([v, l]) => h('option', { value: v, selected: v === t.unite }, l)));
        const form = h('form', { class: 'bf-prix__form' }, h('strong', {}, t.code), nom, desc, h('div', { class: 'bf-filtres' }, un,
          h('button', { class: 'bf-bouton bf-bouton--discret', type: 'submit' }, 'Enregistrer la ligne'),
          h('button', { class: 'bf-lien', type: 'button', onclick: () => form.replaceWith(texte) }, 'Annuler')));
        form.addEventListener('submit', async (ev) => {
          ev.preventDefault();
          try { await api.patch('types-travaux', { nom: nom.value, description: desc.value, unite: un.value }, { id: t.id }); message(msg, `Ligne ${t.code} modifiée. Les demandes déjà envoyées gardent le texte d'origine.`, 'ok'); charger(); }
          catch (e) { message(msg, e.message); }
        });
        texte.replaceWith(form); nom.focus();
      } }, 'Modifier') : null;
      const el = h('div', { class: 'bf-prix' },
        peutDemander ? coche : h('span'),
        texte,
        h('div', { class: 'bf-prix__droite' },
          h('label', { class: 'bf-prix__saisie' }, champ, h('span', { class: 'bf-prix__unite' }, UNITES[t.unite] || t.unite || 'forfait')),
          modifier));
      lignes.push({ el, t, coche });
      return el;
    };
    const parCat = new Map(categories.map((c) => [c.code, []]));
    parCat.set(null, []);
    for (const t of types) (parCat.has(t.categorie) ? parCat.get(t.categorie) : parCat.get(null)).push(t);
    const sections = [...parCat.entries()].filter(([, ts]) => ts.length).map(([code, ts]) => {
      const nom = categories.find((c) => c.code === code)?.nom || 'Autres';
      const toutCocher = peutDemander ? h('button', { class: 'bf-lien', type: 'button', onclick: () => {
        const visibles = lignes.filter((x) => ts.includes(x.t) && !x.el.hidden);
        const tous = visibles.every((x) => x.coche.checked);
        visibles.forEach((x) => { x.coche.checked = !tous; if (!tous) choisis.add(x.t.id); else choisis.delete(x.t.id); });
        majDemande();
      } }, 'Tout cocher | décocher') : null;
      const sec = h('section', { class: 'bf-prix-section' },
        h('div', { class: 'bf-titre' }, h('h2', { class: 'bf-prix-section__titre' }, `HVAC | ${nom}`), toutCocher), ts.map(ligne));
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
      DEMANDES_PAR_LIEN && peutDemander ? h('section', { class: 'bf-carte-section' }, h('h2', {}, 'Demandes de prix envoyées'), listeDemandes) : null,
      resultatLien,
      peutDemander && !DEMANDES_PAR_LIEN ? h('p', {}, 'Coche les travaux confiés à ce sous-traitant : il les voit dans son portail (« Ma liste de prix ») et y met ses prix lui-même. ',
        fournisseur ? h('a', { href: `/mes-prix?fournisseur=${fournisseur}` }, 'Voir sa liste de prix et ses soumissions actives →') : null) : null,
      recherche,
      sections.map((s) => s.sec),
      (admin || peutDemander) ? h('div', { class: 'bf-prix-barre' },
        peutDemander && DEMANDES_PAR_LIEN ? messageDemande : null, peutDemander && DEMANDES_PAR_LIEN ? boutonDemande : null,
        peutDemander && !DEMANDES_PAR_LIEN ? boutonConfies : null,
        admin ? bouton : null) : null,
      admin ? h('section', { class: 'bf-carte-section' }, h('h2', {}, 'Ajouter un travail à la liste'), formType) : null);
    appliquerFiltre();
    majDemande();
    if (lienCree) { afficherLien(lienCree.d, lienCree.nomSt); lienCree = null; }
  }
  charger();
}
