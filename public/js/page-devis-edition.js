import { initPage, estApprobateur } from './bf-page.js?v=0.3.0';
import { api } from './bf-api.js?v=0.3.0';
import { remplir, h, message, param, dateFr, pct, pastilleStatut } from './bf-dom.js?v=0.3.0';
import { formatCents } from './bf-money.js?v=0.3.0';

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const id = param('id');

  const action = async (fn) => {
    message(msg, '');
    try { await fn(); await charger(); } catch (e) { message(msg, e.message); }
  };

  // Saisie d'un pourcentage (ex. « 5 » ou « 5,5 ») -> points de base
  const versBp = (texte) => Math.round(Number(String(texte).replace(',', '.')) * 100);

  async function charger() {
    let d;
    try { d = await api.get('devis-get', { id }); } catch (e) { remplir(zone, msg); message(msg, e.message); return; }
    const { devis: dv, lignes, approbations, client: c, site } = d;
    const brouillon = dv.statut === 'brouillon';
    const statut = dv.statut_effectif;
    const approDe = (ligneId) => approbations.filter((a) => a.devis_ligne_id === ligneId).at(-1);

    const etatRabais = (l) => {
      if (!l.approbation_requise) return l.rabais_bp ? h('span', { class: 'bf-muet' }, `≤ plafond ${pct(l.plafond_bp)}`) : null;
      const a = approDe(l.id);
      const couvert = a?.statut === 'approuvee' && a.rabais_bp >= l.rabais_bp
        && (a.rabais_mode ?? null) === (l.rabais_mode ?? null) && (a.rabais_valeur ?? 0) >= (l.rabais_valeur ?? 0);
      if (couvert) return h('span', { class: 'bf-pastille bf-pastille--accepte' }, 'Rabais approuvé');
      if (a?.statut === 'en_attente') return h('span', { class: 'bf-pastille bf-pastille--attente' }, 'En attente de Simon ou Mike');
      return h('span', {},
        h('span', { class: 'bf-pastille bf-pastille--refuse' }, a?.statut === 'refusee' ? 'Rabais refusé'
          : l.type_ligne === 'rabais' ? 'À faire approuver' : a?.statut === 'approuvee' ? 'Rabais modifié : réapprouver' : `Au-dessus du plafond (${pct(l.plafond_bp)})`),
        ' ', h('button', { class: 'bf-lien', type: 'button', onclick: () => action(async () => {
          const motif = prompt('Pourquoi ce rabais ? (visible par Simon et Mike)');
          if (!motif) return;
          await api.post('approbations', { devis_ligne_id: l.id, motif });
        }) }, 'Demander l\'approbation'));
    };

    const libelleRabais = (l) => (l.rabais_mode === 'pourcentage' ? pct(l.rabais_valeur) : formatCents(l.rabais_valeur));
    const ligneRabaisEl = (l) => {
      const mode = h('select', { disabled: !brouillon, 'aria-label': 'Type de rabais' },
        h('option', { value: 'montant', selected: l.rabais_mode === 'montant' }, '$'), h('option', { value: 'pourcentage', selected: l.rabais_mode === 'pourcentage' }, '%'));
      const valeur = h('input', { inputmode: 'decimal', class: 'bf-court', disabled: !brouillon, 'aria-label': 'Valeur du rabais',
        value: String(l.rabais_mode === 'pourcentage' ? l.rabais_valeur / 100 : l.rabais_valeur / 100).replace('.', ',') });
      const enregistrer = () => action(() => api.patch('devis-lignes', { rabais_mode: mode.value, rabais_valeur: Math.round(Number(valeur.value.replace(',', '.').replace(/\s/g, '')) * 100) }, { id: l.id }));
      mode.addEventListener('change', enregistrer);
      valeur.addEventListener('change', enregistrer);
      return h('tr', { class: 'bf-ligne-rabais' },
        h('td', {}, l.description, h('div', { class: 'bf-muet' }, `Rabais global : ${libelleRabais(l)}`)),
        h('td', {}), h('td', {}),
        h('td', { class: 'num' }, valeur, ' ', mode),
        h('td', { class: 'num' }, formatCents(l.montant_cents)),
        h('td', {}, etatRabais(l)),
        h('td', {}, brouillon ? h('button', { class: 'bf-lien', type: 'button', onclick: () => action(() => api.del('devis-lignes', { id: l.id })) }, 'Retirer') : null));
    };

    const ligneEl = (l) => {
      if (l.type_ligne === 'rabais') return ligneRabaisEl(l);
      const qte = h('input', { type: 'number', min: '0.01', step: '0.01', value: l.quantite, disabled: !brouillon, 'aria-label': 'Quantité', class: 'bf-court' });
      const rabais = h('input', { type: 'text', inputmode: 'decimal', value: String(l.rabais_bp / 100).replace('.', ','), disabled: !brouillon, 'aria-label': 'Rabais en %', class: 'bf-court' });
      const enregistrer = () => action(() => api.patch('devis-lignes', { quantite: Number(qte.value), rabais_bp: versBp(rabais.value) }, { id: l.id }));
      qte.addEventListener('change', enregistrer);
      rabais.addEventListener('change', enregistrer);
      return h('tr', {},
        h('td', {}, l.description, l.kit_id ? h('span', { class: 'bf-muet' }, ' (kit)') : null,
          l.type_ligne === 'installation' ? h('div', { class: 'bf-muet bf-interne' },
            `Interne : coût ${formatCents(l.cout_cents)} (${l.source_cout === 'soumission' ? `soumission ${l.reference_soumission}` : 'grille'})`,
            ` + marge ${pct(l.marge_bp)}`) : null),
        h('td', { class: 'num' }, qte),
        h('td', { class: 'num' }, formatCents(l.prix_unitaire_cents)),
        h('td', { class: 'num' }, rabais, ' %'),
        h('td', { class: 'num' }, formatCents(l.montant_cents)),
        h('td', {}, etatRabais(l)),
        h('td', {}, brouillon ? h('button', { class: 'bf-lien', type: 'button', 'aria-label': `Retirer ${l.description}`,
          onclick: () => action(() => api.del('devis-lignes', { id: l.id })) }, 'Retirer') : null));
    };

    // Ajout depuis le catalogue (produits et kits) ou ligne libre
    const resultats = h('div', { class: 'bf-liste' });
    const rechercheCat = h('input', { type: 'search', placeholder: 'Chercher un produit ou un kit (2 lettres min.)', 'aria-label': 'Catalogue' });
    let minuterie;
    rechercheCat.addEventListener('input', () => {
      clearTimeout(minuterie);
      minuterie = setTimeout(async () => {
        try {
          const { produits, kits } = await api.get('catalogue-search', { q: rechercheCat.value });
          const ajouter = (corps) => action(async () => { await api.post('devis-lignes', { devis_id: dv.id, quantite: 1, ...corps }); rechercheCat.value = ''; resultats.replaceChildren(); });
          resultats.replaceChildren(
            ...kits.map((k) => h('button', { class: 'bf-ligne', type: 'button', onclick: () => ajouter({ kit_id: k.id }) },
              h('strong', {}, `Kit | ${k.nom}`), h('span', {}, formatCents(k.prix_cents)), k.fictif ? h('span', { class: 'bf-muet' }, 'FICTIF') : null)),
            ...produits.map((p) => h('button', { class: 'bf-ligne', type: 'button', onclick: () => ajouter({ produit_id: p.id }) },
              h('strong', {}, p.nom), h('span', { class: 'bf-muet' }, p.sku), h('span', {}, formatCents(p.prix_cents)), p.fictif ? h('span', { class: 'bf-muet' }, 'FICTIF') : null)));
        } catch (e) { message(msg, e.message); }
      }, 250);
    });
    // Installation : coût du sous-traitant + marge, calculés par la base
    const formInst = h('form', { class: 'bf-form bf-form--compact' });
    if (brouillon) {
      api.get('installation-options').then(({ types, sousTraitants, grille, margeBp }) => {
        const coutGrille = (st, ty) => grille.find((g) => g.fournisseur_id === st && g.type_travail_id === ty)?.cout_cents;
        const selType = h('select', { name: 'type', required: true, 'aria-label': 'Type de travail' },
          h('option', { value: '' }, 'Type de travail…'), types.map((t) => h('option', { value: t.id }, t.nom)));
        const selSt = h('select', { name: 'st', required: true, 'aria-label': 'Sous-traitant' },
          h('option', { value: '' }, 'Sous-traitant…'), sousTraitants.map((f) => h('option', { value: f.id }, f.nom)));
        const soum = h('input', { type: 'checkbox', name: 'soumission' });
        const cout = h('input', { name: 'cout', inputmode: 'decimal', placeholder: 'Coût soumission $', class: 'bf-court', hidden: true, 'aria-label': 'Coût de la soumission' });
        const ref = h('input', { name: 'ref', placeholder: 'No de soumission', hidden: true, 'aria-label': 'Numéro de soumission' });
        const apercu = h('span', { class: 'bf-muet' });
        const majApercu = () => {
          const c = soum.checked ? Math.round(Number(String(cout.value).replace(',', '.').replace(/\s/g, '')) * 100) : coutGrille(selSt.value, selType.value);
          apercu.textContent = c > 0 ? `Coût ${formatCents(c)} | prix client ${formatCents(Math.round(c * 10000 / (10000 - margeBp)))} (marge ${pct(margeBp)})`
            : (selSt.value && selType.value && !soum.checked ? 'Aucun prix dans la grille : coche « Soumission »' : '');
        };
        soum.addEventListener('change', () => { cout.hidden = ref.hidden = !soum.checked; majApercu(); });
        [selType, selSt, cout].forEach((el) => el.addEventListener('input', majApercu));
        formInst.addEventListener('submit', (ev) => {
          ev.preventDefault();
          const corps = { devis_id: dv.id, type_ligne: 'installation', type_travail_id: selType.value, sous_traitant_id: selSt.value, quantite: 1 };
          if (soum.checked) Object.assign(corps, { source_cout: 'soumission', reference_soumission: ref.value,
            cout_cents: Math.round(Number(String(cout.value).replace(',', '.').replace(/\s/g, '')) * 100) });
          action(() => api.post('devis-lignes', corps));
        });
        remplir(formInst, h('strong', {}, 'Installation (sous-traitant + marge)'),
          h('div', { class: 'bf-filtres' }, selType, selSt, h('label', { class: 'bf-case' }, soum, 'Soumission pour ce job'), cout, ref,
            h('button', { class: 'bf-bouton bf-bouton--discret', type: 'submit' }, 'Ajouter l\'installation')),
          apercu);
      }).catch((e) => message(msg, e.message));
    }

    const formRabais = h('form', { class: 'bf-filtres' },
      h('select', { name: 'mode', 'aria-label': 'Type de rabais global' }, h('option', { value: 'montant' }, 'Rabais global en $'), h('option', { value: 'pourcentage' }, 'Rabais global en %')),
      h('input', { name: 'valeur', inputmode: 'decimal', placeholder: 'Valeur', required: true, class: 'bf-court', 'aria-label': 'Valeur du rabais global' }),
      h('button', { class: 'bf-bouton bf-bouton--discret', type: 'submit' }, 'Ajouter le rabais'),
      h('span', { class: 'bf-muet' }, 'Toujours approuvé par Simon ou Mike'));
    formRabais.addEventListener('submit', (ev) => {
      ev.preventDefault();
      const f = new FormData(formRabais);
      const v = Math.round(Number(String(f.get('valeur')).replace(',', '.').replace(/\s/g, '')) * 100);
      action(() => api.post('devis-lignes', { devis_id: dv.id, type_ligne: 'rabais', rabais_mode: f.get('mode'), rabais_valeur: v }));
    });

    const formLibre = h('form', { class: 'bf-filtres' },
      h('input', { name: 'description', placeholder: 'Ligne libre (ex. main-d\'oeuvre supplémentaire)', required: true, 'aria-label': 'Description' }),
      h('input', { name: 'prix', inputmode: 'decimal', placeholder: 'Prix $', required: true, class: 'bf-court', 'aria-label': 'Prix unitaire' }),
      h('button', { class: 'bf-bouton bf-bouton--discret', type: 'submit' }, 'Ajouter'));
    formLibre.addEventListener('submit', (ev) => {
      ev.preventDefault();
      const f = new FormData(formLibre);
      const cents = Math.round(Number(String(f.get('prix')).replace(',', '.').replace(/\s/g, '')) * 100);
      action(() => api.post('devis-lignes', { devis_id: dv.id, description: f.get('description'), prix_unitaire_cents: cents, quantite: 1 }));
    });

    const changer = (s, confirmer) => action(async () => {
      if (confirmer && !confirm(confirmer)) return;
      const corps = { id: dv.id, statut: s };
      if (s === 'refuse') corps.raison_refus = prompt('Raison du refus du client (optionnel)') || undefined;
      await api.post('devis-statut', corps);
    });
    const renouveler = () => action(async () => {
      const { id: nouveau } = await api.post('devis-renouveler', { id: dv.id });
      location.href = `/devis-edition?id=${nouveau}`;
    });

    const boutons = [];
    if (brouillon) boutons.push(h('button', { class: 'bf-bouton', type: 'button', disabled: dv.bloque_par_rabais || !lignes.length,
      title: dv.bloque_par_rabais ? 'Un rabais attend l\'approbation de Simon ou Mike' : null,
      onclick: () => changer('envoye', 'Envoyer ce devis ? Les lignes seront figées et il sera valide 30 jours.') }, 'Envoyer au client'));
    if (statut === 'envoye') {
      boutons.push(h('button', { class: 'bf-bouton', type: 'button', onclick: () => changer('accepte', 'Le client accepte ce devis ?') }, 'Accepté par le client'));
      boutons.push(h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => changer('refuse') }, 'Refusé'));
    }
    if (['expire', 'refuse', 'annule', 'envoye'].includes(statut)) boutons.push(h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: renouveler }, 'Renouveler (extension E01, E02...)'));
    if (['brouillon', 'envoye'].includes(dv.statut)) boutons.push(h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => changer('annule', 'Annuler ce devis ? Son numéro reste utilisé.') }, 'Annuler'));
    boutons.push(h('a', { class: 'bf-bouton bf-bouton--discret', href: `/devis-imprimer?id=${dv.id}`, target: '_blank', rel: 'noopener' }, 'Imprimer / PDF'));

    const nomClient = [c.prenom, c.nom].filter(Boolean).join(' ') || c.entreprise;
    const depot = h('select', { disabled: !brouillon, 'aria-label': 'Dépôt' }, [4000, 2500, 5000, 0].map((bp) =>
      h('option', { value: bp, selected: bp === dv.depot_bp }, `Dépôt ${pct(bp)}`)));
    depot.addEventListener('change', () => action(() => api.patch('devis-update', { depot_bp: Number(depot.value) }, { id: dv.id })));
    const notes = h('textarea', { rows: 3, disabled: !brouillon, 'aria-label': 'Notes au client' }, dv.notes_client || '');
    notes.addEventListener('change', () => action(() => api.patch('devis-update', { notes_client: notes.value }, { id: dv.id })));

    remplir(zone, 
      h('p', {}, h('a', { href: '/devis' }, '← Devis'), ' | ', h('a', { href: `/client?id=${c.id}` }, nomClient)),
      h('div', { class: 'bf-titre' }, h('h1', {}, `Devis #${dv.numero}`), pastilleStatut(statut)),
      h('p', { class: 'bf-muet' },
        `Projet ${dv.code_projet} | ${dv.succursale_code} | ${dv.vendeur_nom || ''} | créé le ${dateFr(dv.date_devis)}`,
        dv.statut !== 'brouillon' ? ` | valide jusqu'au ${dateFr(dv.valide_jusqu)}` : '',
        site ? ` | ${site.adresse}, ${site.ville}` : ''),
      msg,
      statut === 'expire' ? h('p', { class: 'bf-message bf-message--alerte' }, 'Ce devis est expiré (30 jours). Renouvelle-le : il garde son code projet avec une extension (E01, E02...) et reprend les prix à jour.') : null,
      estApprobateur(user) && approbations.some((a) => a.statut === 'en_attente')
        ? h('p', { class: 'bf-message bf-message--alerte' }, 'Une demande de rabais attend ta décision : ', h('a', { href: '/devis' }, 'voir les approbations')) : null,
      h('div', { class: 'bf-table-zone' }, h('table', { class: 'bf-table' },
        h('thead', {}, h('tr', {}, ['Description', 'Qté', 'Prix', 'Rabais', 'Montant', '', ''].map((t) => h('th', {}, t)))),
        h('tbody', {}, lignes.length ? lignes.map(ligneEl) : h('tr', {}, h('td', { colspan: 7, class: 'bf-muet' }, 'Aucune ligne. Ajoute un produit ou un kit.'))))),
      brouillon ? h('section', { class: 'bf-carte-section' }, h('h2', {}, 'Ajouter'), rechercheCat, resultats, formInst, formLibre, lignes.some((l) => l.type_ligne === 'rabais') ? null : formRabais) : null,
      h('section', { class: 'bf-totaux' },
        h('dl', { class: 'bf-dl' },
          h('dt', {}, 'Sous-total'), h('dd', { class: 'num' }, formatCents(dv.sous_total_cents)),
          dv.rabais_cents ? [h('dt', {}, 'Rabais inclus'), h('dd', { class: 'num' }, formatCents(dv.rabais_cents))] : null,
          h('dt', {}, 'TPS (5 %)'), h('dd', { class: 'num' }, formatCents(dv.tps_cents)),
          h('dt', {}, 'TVQ (9,975 %)'), h('dd', { class: 'num' }, formatCents(dv.tvq_cents)),
          h('dt', { class: 'fort' }, 'Total'), h('dd', { class: 'num fort' }, formatCents(dv.total_cents)),
          h('dt', {}, depot), h('dd', { class: 'num' }, formatCents(dv.depot_cents)),
          h('dt', {}, 'Solde (72 h avant l\'installation)'), h('dd', { class: 'num' }, formatCents(dv.total_cents - dv.depot_cents)))),
      h('section', { class: 'bf-carte-section' }, h('h2', {}, 'Notes au client'), notes),
      h('div', { class: 'bf-actions' }, boutons));
  }
  charger();
}
