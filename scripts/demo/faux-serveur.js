// Faux serveur en mémoire pour le HTML de test (npm run demo). Code navigateur, chargé par la coquille.
// Il imite les fonctions Netlify et les règles de la base (tour de rôle, horodatage, cotes, RLS simplifiée).
// Données 100 % fictives. Rien n'est envoyé nulle part ; tout repart à zéro au rechargement.
/* global window */
(function () {
  const H = 3600e3, M = 60e3;
  const UTILISATEURS = {
    simon:  { id: 'e-simon',  itemId: null, email: 'simon@exemple.invalid', name: 'Simon Cardinal', role: 'Admin tout', succursale: 'HO', peutApprouverRabais: true, masterImpersonation: null, sousTraitantId: null },
    marc:   { id: 'e-marc',   itemId: null, email: 'marc@exemple.invalid', name: 'Marc Vendeur (FICTIF)', role: 'Vendeur', succursale: 'RO', peutApprouverRabais: false, masterImpersonation: null, sousTraitantId: null },
    sophie: { id: 'e-sophie', itemId: null, email: 'sophie@exemple.invalid', name: 'Sophie Vente (FICTIF)', role: 'Vendeur', succursale: 'ST', peutApprouverRabais: false, masterImpersonation: null, sousTraitantId: null },
    karim:  { id: 'e-karim',  itemId: null, email: 'karim@exemple.invalid', name: 'Karim Ventes (FICTIF)', role: 'Vendeur', succursale: 'GA', peutApprouverRabais: false, masterImpersonation: null, sousTraitantId: null },
    clim:   { id: 'e-clim',   itemId: null, email: 'clim@exemple.invalid', name: 'Clim Laurentides (FICTIF)', role: 'Sous-traitant', succursale: 'HO', peutApprouverRabais: false, masterImpersonation: null, sousTraitantId: 'f-clim' },
  };
  const EMPLOYES = Object.values(UTILISATEURS).filter((u) => !u.sousTraitantId).map((u) => {
    const [prenom, ...reste] = u.name.split(' ');
    return { id: u.id, prenom, nom: reste.join(' '), role: u.role, succursale_code: u.succursale, actif: true };
  });
  const nomEmp = (id) => { const e = EMPLOYES.find((x) => x.id === id); return e ? `${e.prenom} ${e.nom}` : null; };
  const BOARD = ['Admin tout', 'Direction', 'Gérant de succursale', 'Coordonnateur'];

  const etat = {
    qui: 'simon',
    maintenant: (() => { const d = new Date(); d.setHours(11, 0, 0, 0); return d.getTime(); })(),
    leads: [], activites: [], compteur: 0, pointeurs: {},
    vendeurs: [{ employe_id: 'e-marc', ordre: 1, actif: true, types: ['mural_simple', 'mural_multi'] }, { employe_id: 'e-sophie', ordre: 2, actif: true, types: ['mural_simple', 'mural_multi', 'central', 'bienergie'] }, { employe_id: 'e-karim', ordre: 3, actif: false, types: ['mural_simple'] }],
    objectifs: [
      { indicateur: 'minutes_prise_en_charge', libelle: 'Délai de prise en charge (médiane)', unite: 'minutes', sens: 'bas', seuil_bon: null, seuil_moyen: null, ordre: 1 },
      { indicateur: 'minutes_premier_contact', libelle: 'Délai du premier contact (médiane)', unite: 'minutes', sens: 'bas', seuil_bon: null, seuil_moyen: null, ordre: 2 },
      { indicateur: 'pct_contactes', libelle: 'Leads contactés', unite: 'pourcent', sens: 'haut', seuil_bon: null, seuil_moyen: null, ordre: 3 },
      { indicateur: 'pct_premier_par_appel', libelle: 'Premier contact fait par appel téléphonique', unite: 'pourcent', sens: 'haut', seuil_bon: null, seuil_moyen: null, ordre: 4 },
      { indicateur: 'pct_visites', libelle: 'Leads avec visite planifiée', unite: 'pourcent', sens: 'haut', seuil_bon: null, seuil_moyen: null, ordre: 5 },
    ],
    clients: [], sites: [],
    fournisseurs: [
      { id: 'f-clim', nom: 'Clim Laurentides (FICTIF)', type: 'sous-traitant', telephone: '450-555-0190', courriel: 'clim@exemple.invalid', licence_rbq: '0000-0000-00', responsable_nom: 'Martin Lavoie (FICTIF)', responsable_telephone: '450-555-0191', responsable_courriel: 'martin@exemple.invalid', proprietaire_nom: 'Paul Lavoie (FICTIF)', actif: true },
      { id: 'f-rive', nom: 'Climatisation Rive-Nord (FICTIF)', type: 'sous-traitant', telephone: '450-555-0177', courriel: 'rivenord@exemple.invalid', licence_rbq: '0000-0000-02', responsable_nom: 'Julie Roy (FICTIF)', responsable_telephone: '450-555-0178', responsable_courriel: 'julie@exemple.invalid', proprietaire_nom: 'Julie Roy (FICTIF)', actif: true },
      { id: 'f-mauri', nom: 'Froid Centre-du-Québec (FICTIF)', type: 'sous-traitant', telephone: '819-555-0123', courriel: 'froid@exemple.invalid', licence_rbq: '0000-0000-03', responsable_nom: 'Éric Bélanger (FICTIF)', responsable_telephone: '819-555-0124', responsable_courriel: 'eric@exemple.invalid', proprietaire_nom: 'Nadia Côté (FICTIF)', actif: true },
      { id: 'f-outa', nom: 'Thermo Outaouais (FICTIF)', type: 'sous-traitant', telephone: '819-555-0144', courriel: 'thermo@exemple.invalid', licence_rbq: null, responsable_nom: 'Kevin Hall (FICTIF)', responsable_telephone: '819-555-0145', responsable_courriel: 'kevin@exemple.invalid', proprietaire_nom: null, actif: true },
    ],
    territoire: [], principaux: [], dispos: [],
    types: (window.__demoTypesTravaux || []).map((x, i) => ({ id: `t-${x.code}`, code: x.code, nom: x.nom, description: x.inclus, categorie: x.categorie, unite: x.unite, ordre: i })),
    categories: (window.__demoCategories || []).map(([code, nom], i) => ({ code, nom, ordre: i + 1 })),
    tarifs: [
      { fournisseur_id: 'f-clim', type_travail_id: 't-INST-MURAL-1T-12', cout_cents: 120000, en_vigueur_du: '2026-01-01' },
      { fournisseur_id: 'f-clim', type_travail_id: 't-INST-TETE-MULTI', cout_cents: 60000, en_vigueur_du: '2026-01-01' },
      { fournisseur_id: 'f-outa', type_travail_id: 't-INST-MURAL-1T-12', cout_cents: 115000, en_vigueur_du: '2026-01-01' },
    ],
    margeBp: 2500,
    demandes: [], dernierLien: null,
    confies: [], versions: [],
    // Soumissions actives fictives (devis faits dans l'app de Mike) qui utilisent les prix de Clim Laurentides
    engagements: [],
    municipalites: [],
  };
  const user = () => UTILISATEURS[etat.qui];
  const voitBoard = () => BOARD.includes(user().role);

  // ---------- Leads ----------
  const NOMS = ['Julie Tremblay', 'Éric Gagnon', 'Nadia Roy', 'Luc Bélanger', 'Chantal Côté', 'Patrick Lavoie', 'Isabelle Fortin', 'Martin Pelletier', 'Annie Bouchard', 'Simon-Pierre Morin', 'Karine Gauthier', 'Yves Ouellet'];
  const VILLES = ['Saint-Jérôme', 'Rosemère', 'Blainville', 'Saint-Sauveur', 'Mirabel', 'Gatineau', 'Drummondville', 'Prévost', 'Sainte-Adèle', 'Terrebonne'];
  const BESOINS = ['Thermopompe murale pour le salon', 'Climatisation centrale, maison 1990', 'Remplacement fournaise et thermopompe', 'Multizone 3 têtes, condo', 'Info subvention LogisVert'];
  // Tour de rôle par type, entre les vendeurs actifs qualifiés (type inconnu : tous les actifs)
  function prochainVendeur(type) {
    const cle = type || 'tous';
    const actifs = etat.vendeurs.filter((v) => v.actif && (!type || v.types.includes(type))).sort((a, b) => a.ordre - b.ordre).map((v) => v.employe_id);
    if (!actifs.length) return null;
    etat.pointeurs[cle] = actifs[(actifs.indexOf(etat.pointeurs[cle]) + 1) % actifs.length];
    return etat.pointeurs[cle];
  }
  function creerLead(champs, recu = etat.maintenant) {
    const n = etat.compteur++;
    const l = { id: `lead-${n}`, recu_le: recu, source: n % 2 ? 'facebook' : 'google', campagne: n % 2 ? 'Thermopompe automne' : 'Climatisation',
      statut: 'nouveau', contact_nom: `${NOMS[n % NOMS.length]} (FICTIF)`, contact_tel: `450-555-01${String(10 + n).slice(-2)}`,
      contact_courriel: null, ville: VILLES[n % VILLES.length], besoin: BESOINS[n % BESOINS.length], succursale_code: 'RO',
      type_demande: ['mural_simple', 'mural_multi', 'central', 'bienergie', null][n % 5],
      assigne_a: null, attribue_le: null, pris_en_charge_le: null, premier_contact_le: null, premier_contact_canal: null, visite_prevue_le: null, raison_perte: null, ...champs };
    l.assigne_a = prochainVendeur(l.type_demande);
    if (l.assigne_a) { l.attribue_le = recu; activite(l, { type: 'attribution', note: 'Attribué automatiquement (tour de rôle)' }, recu, l.assigne_a); }
    etat.leads.unshift(l);
    return l;
  }
  function activite(l, a, t = etat.maintenant, par = user().id) {
    if (['appel', 'courriel', 'texto'].includes(a.type) && !a.resultat) a.resultat = a.type === 'appel' ? 'joint' : 'envoye';
    etat.activites.push({ id: `act-${etat.activites.length}`, lead_id: l.id, employe_id: par, fait_le: t, ...a });
    if (['prise_en_charge', 'appel', 'courriel', 'texto', 'visite_planifiee'].includes(a.type) && !l.pris_en_charge_le) l.pris_en_charge_le = t;
    if (['appel', 'courriel', 'texto'].includes(a.type) && !l.premier_contact_le) { l.premier_contact_le = t; l.premier_contact_canal = a.type; }
    if (a.type === 'perdu') { l.statut = 'perdu'; l.raison_perte = a.note; }
    else if (a.type === 'reouvert') l.statut = l.premier_contact_le ? 'contacte' : 'pris_en_charge';
    else if (['converti', 'perdu'].includes(l.statut)) { /* fermé */ }
    else if (a.type === 'visite_planifiee') { l.statut = 'inspection_planifiee'; l.visite_prevue_le = a.visite_le; }
    else if (['appel', 'courriel', 'texto'].includes(a.type) && ['nouveau', 'pris_en_charge'].includes(l.statut)) l.statut = 'contacte';
    else if (a.type === 'prise_en_charge' && l.statut === 'nouveau') l.statut = 'pris_en_charge';
  }
  const iso = (t) => (t ? new Date(t).toISOString() : null);
  const minutes = (a, b) => (a && b ? (b - a) / M : null);
  function seuilRetard() { const o = etat.objectifs.find((x) => x.indicateur === 'minutes_premier_contact'); return o.seuil_moyen ?? o.seuil_bon; }
  function vueLead(l) {
    const s = seuilRetard();
    return { ...l, recu_le: iso(l.recu_le), attribue_le: iso(l.attribue_le), pris_en_charge_le: iso(l.pris_en_charge_le),
      premier_contact_le: iso(l.premier_contact_le), visite_prevue_le: l.visite_prevue_le || null, vendeur_nom: nomEmp(l.assigne_a),
      minutes_prise_en_charge: minutes(l.recu_le, l.pris_en_charge_le), minutes_premier_contact: minutes(l.recu_le, l.premier_contact_le),
      minutes_en_attente: minutes(l.recu_le, l.premier_contact_le || etat.maintenant),
      vendeur_qualifie: !l.type_demande || !l.assigne_a || !!etat.vendeurs.find((v) => v.employe_id === l.assigne_a)?.types.includes(l.type_demande),
      en_retard: !l.premier_contact_le && !['perdu', 'converti'].includes(l.statut) && s !== null && (etat.maintenant - l.recu_le) / M > s };
  }
  const visibles = () => etat.leads.filter((l) => voitBoard() || l.assigne_a === user().id);
  const mediane = (xs) => { if (!xs.length) return null; const t = [...xs].sort((a, b) => a - b); const m = t.length >> 1; return Math.round((t.length % 2 ? t[m] : (t[m - 1] + t[m]) / 2) * 10) / 10; };
  function rapidite() {
    const parV = {};
    for (const l of visibles().map(vueLead)) if (l.assigne_a) (parV[l.assigne_a] ||= []).push(l);
    return Object.entries(parV).map(([id, ls]) => {
      const c = ls.filter((l) => l.premier_contact_le);
      const r1 = (x) => Math.round(x * 10) / 10;
      return { employe_id: id, vendeur_nom: nomEmp(id), leads: ls.length, contactes: c.length,
        minutes_prise_en_charge: mediane(ls.filter((l) => l.pris_en_charge_le).map((l) => l.minutes_prise_en_charge)),
        minutes_premier_contact: mediane(c.map((l) => l.minutes_premier_contact)),
        pct_contactes: r1(100 * c.length / ls.length),
        pct_premier_par_appel: c.length ? r1(100 * c.filter((l) => l.premier_contact_canal === 'appel').length / c.length) : null,
        pct_visites: r1(100 * ls.filter((l) => l.visite_prevue_le).length / ls.length),
        par_appel: c.filter((l) => l.premier_contact_canal === 'appel').length, par_courriel: c.filter((l) => l.premier_contact_canal === 'courriel').length, par_texto: c.filter((l) => l.premier_contact_canal === 'texto').length };
    }).sort((a, b) => a.vendeur_nom.localeCompare(b.vendeur_nom));
  }
  function cote(v, o) {
    if (v === null || v === undefined || (o.seuil_bon === null && o.seuil_moyen === null)) return 'non_evalue';
    const ok = (s) => (o.sens === 'bas' ? v <= s : v >= s);
    if (o.seuil_bon !== null && ok(o.seuil_bon)) return 'bon';
    if (o.seuil_moyen === null || ok(o.seuil_moyen)) return 'moyen';
    return 'a_ameliorer';
  }

  // Historique de la matinée (fictif)
  const debut = (() => { const d = new Date(etat.maintenant); d.setHours(9, 0, 0, 0); return d.getTime(); })();
  [[2, 4, 'appel', 'joint', true], [20, 6, 'appel', 'joint', true], [41, 52, 'courriel', null, false], [58, 9, 'appel', 'message_laisse', false],
   [75, 38, 'texto', null, true], [91, 3, 'appel', 'joint', true], [107, 22, 'appel', 'pas_de_reponse', false]].forEach(([dm, delai, canal, res, visite]) => {
    const l = creerLead({}, debut + dm * M);
    activite(l, { type: 'prise_en_charge' }, l.recu_le + Math.max(1, delai - 2) * M, l.assigne_a);
    activite(l, { type: canal, resultat: res || undefined }, l.recu_le + delai * M, l.assigne_a);
    if (visite) activite(l, { type: 'visite_planifiee', visite_le: new Date(l.recu_le + 3 * 24 * H).toISOString() }, l.recu_le + (delai + 3) * M, l.assigne_a);
  });
  creerLead({}, etat.maintenant - 34 * M);
  creerLead({}, etat.maintenant - 6 * M);
  etat.clients.push({ id: 'c-1', type: 'residentiel', prenom: 'Julie', nom: 'Tremblay (FICTIF)', courriel: 'julie@exemple.invalid', telephone: '450-555-0110', succursale_code: 'RO', vendeur_id: 'e-marc', est_proprietaire: true, actif: true });
  etat.sites.push({ id: 's-1', client_id: 'c-1', adresse: '12 rue des Érables (FICTIF)', ville: 'Saint-Jérôme', province: 'QC', code_postal: 'J7Z 0A0' });

  // Travaux confiés et soumissions actives (fictifs)
  const tid = (code) => `t-${code}`;
  for (const code of ['INST-MURAL-1T-12', 'INST-MURAL-1T-18', 'INST-MULTI-2T', 'INST-MULTI-3T', 'INST-TETE-MULTI', 'REMP-MURAL-1T', 'EXTRA-LIGNE-PI', 'EXTRA-POMPE-COND']) etat.confies.push({ fournisseur_id: 'f-clim', type_travail_id: tid(code) });
  etat.tarifs.push({ fournisseur_id: 'f-clim', type_travail_id: tid('INST-MULTI-2T'), cout_cents: 210000, en_vigueur_du: '2026-03-01' },
    { fournisseur_id: 'f-clim', type_travail_id: tid('EXTRA-LIGNE-PI'), cout_cents: 2500, en_vigueur_du: '2026-03-01' });
  // Registre des versions de la liste de prix (ADR-065) : copie figée à chaque changement
  const lignesDe = (f) => {
    const ordreCat = new Map(etat.categories.map((c) => [c.code, c.ordre]));
    return etat.types.filter((t) => etat.confies.some((c) => c.fournisseur_id === f && c.type_travail_id === t.id))
      .sort((a, b) => (ordreCat.get(a.categorie) ?? 99) - (ordreCat.get(b.categorie) ?? 99) || a.ordre - b.ordre)
      .map((t) => { const p = etat.tarifs.find((x) => x.fournisseur_id === f && x.type_travail_id === t.id);
        return { code: t.code, nom: t.nom, categorie: etat.categories.find((c) => c.code === t.categorie)?.nom || t.categorie, unite: t.unite,
          cout_cents: p?.cout_cents ?? null, en_vigueur_du: p?.en_vigueur_du ?? null }; });
  };
  const ecarts = (avant, apres) => {
    const parCode = (l) => new Map(l.map((x) => [x.code, x]));
    const a = parCode(avant); const n = parCode(apres); const out = [];
    for (const x of apres) if (!a.has(x.code)) out.push({ type: 'ajout', code: x.code, nom: x.nom, avant: null, apres: x.cout_cents });
    for (const x of avant) if (!n.has(x.code)) out.push({ type: 'retrait', code: x.code, nom: x.nom, avant: x.cout_cents, apres: null });
    for (const x of apres) if (a.has(x.code) && a.get(x.code).cout_cents !== x.cout_cents) out.push({ type: 'prix', code: x.code, nom: x.nom, avant: a.get(x.code).cout_cents, apres: x.cout_cents });
    return out.sort((x, y) => x.code.localeCompare(y.code));
  };
  // Empreinte de démonstration (la vraie base calcule un SHA-256)
  const empreinte = (txt) => { let h1 = 0x811c9dc5; let h2 = 0x1b873593; for (let i = 0; i < txt.length; i++) { h1 = Math.imul(h1 ^ txt.charCodeAt(i), 16777619); h2 = Math.imul(h2 ^ txt.charCodeAt(i), 2246822519); }
    return Array.from({ length: 8 }, (_, i) => (((i % 2 ? h1 : h2) ^ Math.imul(i + 1, 0x9e3779b9)) >>> 0).toString(16).padStart(8, '0')).join(''); };
  function versionner(f, motif, { quand = etat.maintenant, auteur, parSt, lignes = lignesDe(f) } = {}) {
    const prec = etat.versions.filter((v) => v.fournisseur_id === f).sort((a, b) => b.numero - a.numero)[0];
    const changements = prec ? ecarts(prec.lignes, lignes) : [];
    if (prec && !changements.length) return null;
    if (!prec && !lignes.length) return null;
    const u = user(); const st = parSt ?? Boolean(u.sousTraitantId);
    const v = { id: `v-${etat.versions.length + 1}`, fournisseur_id: f, numero: (prec?.numero || 0) + 1, cree_le: new Date(quand).toISOString(),
      auteur_nom: auteur || (st ? (etat.fournisseurs.find((x) => x.id === f)?.responsable_nom || u.name) : u.name), par_sous_traitant: st, motif,
      lignes: JSON.parse(JSON.stringify(lignes)), changements, nb_lignes: lignes.length, nb_changements: changements.length, empreinte: empreinte(JSON.stringify(lignes)) };
    etat.versions.push(v);
    return v.numero;
  }
  // Historique fictif de Clim Laurentides : 2 modifications par le sous-traitant dans les 30 derniers jours.
  // Une 3e modification dans le HTML de test déclenche l'alerte.
  {
    const J = 24 * H;
    const actuel = () => lignesDe('f-clim');
    const avec = (l, code, cout) => l.map((x) => (x.code === code ? { ...x, cout_cents: cout } : x));
    const v4 = actuel();
    const v3 = avec(v4, 'INST-MURAL-1T-12', 115000);
    const v2 = avec(v3, 'INST-TETE-MULTI', 55000);
    const v1 = v2.filter((x) => x.code !== 'EXTRA-POMPE-COND');
    versionner('f-clim', 'Première version (reprise de la liste existante)', { quand: etat.maintenant - 45 * J, auteur: 'Simon Cardinal', parSt: false, lignes: v1 });
    versionner('f-clim', 'Travaux confiés modifiés par Belleflamme', { quand: etat.maintenant - 33 * J, auteur: 'Simon Cardinal', parSt: false, lignes: v2 });
    versionner('f-clim', 'Prix modifiés par le sous-traitant', { quand: etat.maintenant - 12 * J - 3 * H, auteur: 'Martin Lavoie (FICTIF)', parSt: true, lignes: v3 });
    versionner('f-clim', 'Prix modifiés par le sous-traitant', { quand: etat.maintenant - 4 * J + 2 * H, auteur: 'Martin Lavoie (FICTIF)', parSt: true, lignes: v4 });
  }

  const jourPlus = (j) => new Date(etat.maintenant + j * 24 * H).toISOString().slice(0, 10);
  const eng = (numero, ville, vendeur, code, travail, cout, jours, statut = 'envoye') => ({ fournisseur_id: 'f-clim', devis_id: `d-${numero}`, numero, statut, ville, vendeur_nom: vendeur,
    type_travail_id: tid(code), code, travail, quantite: 1, cout_cents: cout, honorer_jusqu: statut === 'accepte' ? null : jourPlus(jours) });
  etat.engagements.push(
    eng('122431', 'Saint-Jérôme', 'Marc Vendeur (FICTIF)', 'INST-MURAL-1T-12', 'Murale 1 tête, jusqu\'à 12 000 BTU', 120000, 12),
    eng('122458', 'Prévost', 'Sophie Vente (FICTIF)', 'INST-MURAL-1T-12', 'Murale 1 tête, jusqu\'à 12 000 BTU', 120000, 27),
    eng('122470', 'Sainte-Adèle', 'Sophie Vente (FICTIF)', 'INST-MULTI-2T', 'Multizone 2 têtes', 210000, 19),
    eng('122395', 'Mirabel', 'Marc Vendeur (FICTIF)', 'INST-MULTI-2T', 'Multizone 2 têtes', 210000, 0, 'accepte'));

  // ---------- Routeur des fonctions ----------
  class Erreur extends Error { constructor(status, message) { super(message); this.status = status; } }
  const exiger = (cond, msg) => { if (!cond) throw new Erreur(400, msg); };
  // Territoires fictifs qui se chevauchent (carte comparative, ADR-063), semés une fois que les municipalités sont chargées
  let semes = false;
  function semerTerritoires() {
    if (semes || !etat.municipalites.length) return;
    semes = true;
    const ajouter = (f, filtre, statut = 'accepte', supplement = null) => {
      for (const m of etat.municipalites.filter(filtre)) {
        if (etat.territoire.some((t) => t.fournisseur_id === f && t.municipalite_code === m.code)) continue;
        etat.territoire.push({ fournisseur_id: f, municipalite_code: m.code, statut, supplement_cents: supplement });
      }
    };
    const mrc = (...n) => (m) => n.includes(m.mrc);
    const region = (...n) => (m) => n.includes(m.region);
    ajouter('f-clim', mrc('Antoine-Labelle'), 'supplement', 15000);
    ajouter('f-clim', region('Laurentides'));
    ajouter('f-rive', mrc('Thérèse-De Blainville', 'Deux-Montagnes', 'Mirabel', 'La Rivière-du-Nord', 'Laval', 'Les Moulins'));
    ajouter('f-mauri', mrc('La Rivière-du-Nord'), 'supplement', 25000);
    ajouter('f-mauri', region('Centre-du-Québec', 'Mauricie'));
    ajouter('f-outa', (m) => m.nom === 'Saint-Jérôme' || m.mrc === 'Argenteuil' || m.mrc === 'Comtés unis de Prescott and Russell', 'supplement', 20000);
    ajouter('f-outa', (m) => m.region === 'Outaouais' || m.nom === 'Ottawa');
    const code = (nom) => etat.municipalites.find((m) => m.nom === nom)?.code;
    for (const [nom, f] of [['Saint-Jérôme', 'f-clim'], ['Gatineau', 'f-outa'], ['Mirabel', 'f-rive'], ['Drummondville', 'f-mauri'], ['Blainville', 'f-rive']]) {
      if (code(nom)) etat.principaux.push({ municipalite_code: code(nom), fournisseur_id: f });
    }
  }

  const routes = {
    'session-me': () => ({ token: 'demo', user: user() }),
    'session-logout': () => ({ ok: true }),
    leads: {
      GET: (q) => {
        let ls = q.vue === 'mes' ? etat.leads.filter((l) => l.assigne_a === user().id) : visibles();
        if (q.vue !== 'mes' && q.vendeur) ls = ls.filter((l) => l.assigne_a === q.vendeur);
        if (q.statut === 'actifs') ls = ls.filter((l) => !['converti', 'perdu'].includes(l.statut));
        else if (q.statut) ls = ls.filter((l) => l.statut === q.statut);
        return ls.map(vueLead);
      },
      POST: (_q, b) => {
        exiger(b.contact_nom, 'Champ requis : contact_nom');
        exiger(b.contact_tel || b.contact_courriel, 'Téléphone ou courriel requis');
        return vueLead(creerLead({ contact_nom: b.contact_nom, contact_tel: b.contact_tel || null, contact_courriel: b.contact_courriel || null,
          ville: b.ville || null, source: b.source || 'autre', campagne: null, besoin: b.besoin || null, succursale_code: b.succursale_code,
          type_demande: b.type_demande || null }));
      },
    },
    lead: {
      GET: (q) => {
        const l = visibles().find((x) => x.id === q.id);
        if (!l) throw new Erreur(404, 'Lead introuvable');
        return { lead: vueLead(l), activites: etat.activites.filter((a) => a.lead_id === l.id).map((a) => ({ ...a, fait_le: iso(a.fait_le) })) };
      },
      PATCH: (q, b) => {
        if (!voitBoard()) throw new Erreur(403, 'Seul le responsable du board réattribue un lead');
        const l = etat.leads.find((x) => x.id === q.id);
        if (b.type_demande !== undefined) l.type_demande = b.type_demande;
        if (b.assigne_a && b.assigne_a !== l.assigne_a) {
          l.assigne_a = b.assigne_a; l.attribue_le = etat.maintenant; l.pris_en_charge_le = null;
          activite(l, { type: 'attribution', note: `Réattribué par ${user().name}` });
        }
        return vueLead(l);
      },
    },
    'lead-activite': {
      POST: (q, b) => {
        const l = visibles().find((x) => x.id === q.id);
        if (!l) throw new Erreur(403, 'Ce lead est attribué à un autre vendeur');
        exiger(!(b.type === 'visite_planifiee' && !b.visite_le), 'Date de visite requise');
        exiger(!(b.type === 'perdu' && !String(b.note || '').trim()), 'Raison de la perte requise');
        activite(l, { type: b.type, resultat: b.resultat, note: b.note, visite_le: b.visite_le });
        return { ok: true };
      },
    },
    'crm-rapidite': {
      GET: () => {
        const vendeurs = rapidite();
        const evaluation = [];
        for (const v of vendeurs) for (const o of etat.objectifs) evaluation.push({ employe_id: v.employe_id, indicateur: o.indicateur, valeur: v[o.indicateur], cote: cote(v[o.indicateur], o) });
        return { objectifs: etat.objectifs, vendeurs, evaluation };
      },
      PUT: (_q, b) => {
        if (!voitBoard()) throw new Erreur(403, 'Modification refusée (droits insuffisants)');
        for (const x of b.objectifs || []) {
          const o = etat.objectifs.find((y) => y.indicateur === x.indicateur);
          const val = (v) => (v === '' || v === null || v === undefined ? null : Number(String(v).replace(',', '.')));
          const bon = val(x.seuil_bon), moyen = val(x.seuil_moyen);
          if (bon !== null && moyen !== null && (o.sens === 'bas' ? bon > moyen : bon < moyen)) throw new Erreur(400, `${o.libelle} : le seuil « bon » doit être plus exigeant que « moyen »`);
          o.seuil_bon = bon; o.seuil_moyen = moyen;
        }
        return etat.objectifs;
      },
    },
    'crm-vendeurs': {
      GET: () => ({ membres: etat.vendeurs, employes: EMPLOYES.filter((e) => ['Vendeur', 'Gérant de succursale', 'Direction', 'Admin tout'].includes(e.role)) }),
      PUT: (_q, b) => {
        if (!voitBoard()) throw new Erreur(403, 'Modification refusée (droits insuffisants)');
        for (const v of b.vendeurs || []) {
          const m = etat.vendeurs.find((x) => x.employe_id === v.employe_id);
          const types = Array.isArray(v.types) ? v.types : (m?.types || ['mural_simple', 'mural_multi', 'central', 'bienergie']);
          if (m) Object.assign(m, { ordre: v.ordre, actif: v.actif, types }); else etat.vendeurs.push({ employe_id: v.employe_id, ordre: v.ordre, actif: v.actif, types });
        }
        return etat.vendeurs;
      },
    },
    'clients-list': { GET: (q) => {
      const t = String(q.q || '').toLowerCase();
      return etat.clients.filter((c) => !t || [c.nom, c.prenom, c.courriel, c.telephone].some((v) => String(v || '').toLowerCase().includes(t)));
    } },
    'clients-get': { GET: (q) => { const c = etat.clients.find((x) => x.id === q.id); if (!c) throw new Erreur(404, 'Client introuvable'); return { client: c, sites: etat.sites.filter((s) => s.client_id === c.id), devis: [] }; } },
    'clients-create': { POST: (_q, b) => {
      exiger(b.nom, 'Champ requis : nom');
      const c = { id: `c-${etat.clients.length + 1}`, actif: true, ...b, site: undefined };
      etat.clients.push(c);
      if (b.site?.adresse) etat.sites.push({ id: `s-${etat.sites.length + 1}`, client_id: c.id, province: 'QC', ...b.site });
      return c;
    } },
    'sites-save': { POST: (_q, b) => { const s = { id: `s-${etat.sites.length + 1}`, province: 'QC', ...b }; etat.sites.push(s); return s; } },
    'devis-create': { POST: () => { throw new Erreur(400, 'Le devis se fait dans l\'app de Mike (module en veille ici).'); } },
    'sous-traitant': {
      GET: (q) => {
        const f = etat.fournisseurs.find((x) => x.id === q.id);
        if (!f || (user().sousTraitantId && user().sousTraitantId !== f.id)) throw new Erreur(404, 'Sous-traitant introuvable');
        return f;
      },
      PATCH: (q, b) => {
        const f = etat.fournisseurs.find((x) => x.id === q.id);
        if (!f) throw new Erreur(404, 'Sous-traitant introuvable');
        exiger(['Admin tout', 'Direction', 'Coordonnateur'].includes(user().role), 'Réservé à la planification');
        const c = { ...b };
        for (const k of Object.keys(c)) if (typeof c[k] === 'string') c[k] = c[k].trim() || null;
        if ('nom' in c) exiger(c.nom && c.nom.length >= 2, 'Nom de la compagnie requis');
        if (c.licence_rbq) {
          const d = c.licence_rbq.replace(/\D/g, '');
          exiger(d.length === 10 && !/[^\d\s-]/.test(c.licence_rbq), 'Numéro RBQ : 10 chiffres (ex. 1234-5678-90)');
          c.licence_rbq = `${d.slice(0, 4)}-${d.slice(4, 8)}-${d.slice(8)}`;
        }
        for (const k of ['courriel', 'responsable_courriel']) if (c[k]) exiger(/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(c[k]), 'Courriel invalide');
        Object.assign(f, c);
        return f;
      },
    },
    'sous-traitants': {
      GET: () => etat.fournisseurs,
      POST: (_q, b) => { exiger(b.nom, 'Champ requis : nom'); const f = { id: `f-${etat.fournisseurs.length + 1}`, type: 'sous-traitant', actif: true, ...b }; etat.fournisseurs.push(f); return { fournisseur: f, compte: { email: b.contact?.email } }; },
    },
    territoire: {
      GET: (q) => {
        semerTerritoires();
        if (q.tous) { exiger(!user().sousTraitantId, 'Réservé à Belleflamme'); return etat.territoire.filter((t) => t.statut !== 'refuse'); }
        const f = user().sousTraitantId || q.fournisseur_id; return etat.territoire.filter((t) => t.fournisseur_id === f);
      },
      POST: (_q, b) => {
        const f = user().sousTraitantId || b.fournisseur_id;
        exiger(Array.isArray(b.municipalites) && b.municipalites.length, 'Liste de municipalités invalide (1 à 2000)');
        if (b.statut === 'supplement') exiger(Number.isInteger(b.supplement_cents) && b.supplement_cents > 0, 'Supplément en cents requis (plus de 0 $)');
        etat.territoire = etat.territoire.filter((t) => !(t.fournisseur_id === f && b.municipalites.includes(t.municipalite_code)));
        if (b.statut !== 'aucun') for (const code of b.municipalites) etat.territoire.push({ fournisseur_id: f, municipalite_code: code, statut: b.statut, supplement_cents: b.statut === 'supplement' ? b.supplement_cents : null });
        return { ok: true };
      },
    },
    principaux: {
      GET: () => { semerTerritoires(); return etat.principaux; },
      POST: (_q, b) => { etat.principaux = etat.principaux.filter((p) => p.municipalite_code !== b.municipalite_code); if (b.fournisseur_id) etat.principaux.push({ municipalite_code: b.municipalite_code, fournisseur_id: b.fournisseur_id }); return { ok: true }; },
    },
    municipalites: { GET: (q) => {
      semerTerritoires();
      if (q.pour) {
        return etat.territoire.filter((t) => t.municipalite_code === q.pour && t.statut !== 'refuse').map((t) => ({
          fournisseur_id: t.fournisseur_id, nom: etat.fournisseurs.find((f) => f.id === t.fournisseur_id)?.nom, statut: t.statut, supplement_cents: t.supplement_cents,
          principal: etat.principaux.some((p) => p.municipalite_code === q.pour && p.fournisseur_id === t.fournisseur_id) }));
      }
      const t = String(q.q || '').toLowerCase();
      if (t.length < 2) return [];
      return etat.municipalites.filter((m) => m.nom.toLowerCase().includes(t)).slice(0, 20);
    } },
    disponibilites: {
      GET: (q) => { const f = user().sousTraitantId || q.fournisseur_id; return etat.dispos.filter((d) => !f || d.fournisseur_id === f); },
      POST: (_q, b) => {
        const f = user().sousTraitantId || b.fournisseur_id;
        for (const j of b.jours || []) {
          etat.dispos = etat.dispos.filter((d) => !(d.fournisseur_id === f && d.jour === j.jour));
          if (j.statut !== 'aucun') etat.dispos.push({ fournisseur_id: f, jour: j.jour, statut: j.statut, note: j.note || null });
        }
        return { ok: true };
      },
    },
    'mes-prix': {
      GET: (q) => {
        const f = user().sousTraitantId || q.fournisseur;
        const ids = new Set(etat.confies.filter((c) => c.fournisseur_id === f).map((c) => c.type_travail_id));
        return { categories: etat.categories,
          travaux: etat.types.filter((t) => ids.has(t.id)).map((t) => { const p = etat.tarifs.find((x) => x.fournisseur_id === f && x.type_travail_id === t.id);
            return { ...t, cout_cents: p?.cout_cents ?? null, en_vigueur_du: p?.en_vigueur_du ?? null }; }),
          engagements: etat.engagements.filter((e) => e.fournisseur_id === f) };
      },
      POST: (_q, b) => {
        const f = user().sousTraitantId || (['Admin tout', 'Direction', 'Coordonnateur'].includes(user().role) ? b.fournisseur_id : null);
        if (!f) throw new Erreur(403, 'Sous-traitant requis');
        let n = 0; const types = [];
        const jour = new Date(etat.maintenant).toISOString().slice(0, 10);
        for (const x of b.prix || []) {
          exiger(Number.isInteger(x.cout_cents) && x.cout_cents > 0, 'Prix invalide');
          if (!etat.confies.some((c) => c.fournisseur_id === f && c.type_travail_id === x.type_travail_id)) {
            // Belleflamme qui met un prix confie le travail du même coup ; le sous-traitant, lui, est refusé
            exiger(!user().sousTraitantId, 'Ce travail n\'est pas confié à ce sous-traitant');
            etat.confies.push({ fournisseur_id: f, type_travail_id: x.type_travail_id });
          }
          const actuel = etat.tarifs.find((t) => t.fournisseur_id === f && t.type_travail_id === x.type_travail_id);
          if (actuel && actuel.cout_cents === x.cout_cents) continue;
          etat.tarifs = etat.tarifs.filter((t) => !(t.fournisseur_id === f && t.type_travail_id === x.type_travail_id));
          etat.tarifs.push({ fournisseur_id: f, type_travail_id: x.type_travail_id, cout_cents: x.cout_cents, en_vigueur_du: jour }); n++; types.push(x.type_travail_id);
        }
        const version = versionner(f, user().sousTraitantId ? 'Prix modifiés par le sous-traitant' : 'Prix modifiés par Belleflamme');
        return { changes: n, version, engagements: etat.engagements.filter((e) => e.fournisseur_id === f && types.includes(e.type_travail_id)) };
      },
    },
    'travaux-confies': { POST: (_q, b) => {
      if (!['Admin tout', 'Direction', 'Coordonnateur'].includes(user().role)) throw new Erreur(403, 'Modification refusée');
      etat.confies = etat.confies.filter((c) => !(c.fournisseur_id === b.fournisseur_id && (b.retirer || []).includes(c.type_travail_id)));
      for (const t of b.ajouter || []) if (!etat.confies.some((c) => c.fournisseur_id === b.fournisseur_id && c.type_travail_id === t)) etat.confies.push({ fournisseur_id: b.fournisseur_id, type_travail_id: t });
      return { ajoutes: (b.ajouter || []).length, retires: (b.retirer || []).length, version: versionner(b.fournisseur_id, 'Travaux confiés modifiés par Belleflamme') };
    } },
    'listes-prix-versions': { GET: (q) => {
      const f = user().sousTraitantId || q.fournisseur;
      exiger(f, 'fournisseur requis');
      exiger(user().sousTraitantId || ['Admin tout', 'Direction', 'Coordonnateur'].includes(user().role), 'Registre réservé à Belleflamme et au sous-traitant');
      const versions = etat.versions.filter((v) => v.fournisseur_id === f).sort((a, b) => b.numero - a.numero);
      const n30 = versions.filter((v) => v.par_sous_traitant && new Date(v.cree_le).getTime() > etat.maintenant - 30 * 24 * H).length;
      return { versions, n30, seuil: 3, alerte: n30 >= 3, jours: 30 };
    } },
    'types-travaux': { PATCH: (q, b) => {
      if (user().role !== 'Admin tout') throw new Erreur(403, 'Modification refusée (Simon ou Mike seulement)');
      const t = etat.types.find((x) => x.id === q.id);
      exiger(t, 'Ligne introuvable');
      if (b.nom !== undefined) { exiger(String(b.nom).trim().length >= 3, 'Titre trop court'); t.nom = String(b.nom).trim(); }
      if (b.description !== undefined) t.description = String(b.description || '').trim() || null;
      if (b.unite) t.unite = b.unite;
      return t;
    } },
    'prix-demandes': {
      GET: (q) => etat.demandes.filter((d) => !q.fournisseur || d.fournisseur_id === q.fournisseur).map(({ jeton, lignes, signature_png, ...d }) => d).reverse(),
      POST: (_q, b) => {
        if (!['Admin tout', 'Direction', 'Coordonnateur'].includes(user().role)) throw new Erreur(403, 'Seuls Simon, Mike et la planification envoient une demande de prix');
        exiger((b.types || []).length, 'Coche au moins un travail');
        const jeton = Array.from({ length: 64 }, () => '0123456789abcdef'[Math.floor(Math.random() * 16)]).join('');
        const d = { id: `dp-${etat.demandes.length + 1}`, jeton, fournisseur_id: b.fournisseur_id, statut: 'envoyee', message: b.message || null,
          created_at: new Date(etat.maintenant).toISOString(), expire_le: new Date(etat.maintenant + 30 * 24 * H).toISOString(), ouverte_le: null,
          signataire_nom: null, signe_le: null, valide_jusqu: null, signature_png: null,
          lignes: etat.types.filter((t) => b.types.includes(t.id)).map((t) => ({ id: `${t.id}-l`, type_travail_id: t.id, code: t.code, nom: t.nom, description: t.description, unite: t.unite, categorie: t.categorie, ordre: t.ordre, cout_cents: null, non_offert: false, note: null })) };
        etat.demandes.push(d);
        etat.dernierLien = `/prix#${jeton}`;
        return { id: d.id, expire_le: d.expire_le, lien: `https://hvac.belleflamme.exemple/prix#${jeton}` };
      },
    },
    'prix-demande': {
      GET: (q) => { const d = etat.demandes.find((x) => x.id === q.id); if (!d) throw new Erreur(404, 'Demande introuvable'); const { jeton, lignes, ...demande } = d; return { demande, lignes }; },
      POST: (q) => {
        const d = etat.demandes.find((x) => x.id === q.id);
        if (q.action === 'annuler') { exiger(['envoyee', 'recue'].includes(d.statut), 'Déjà traitée'); d.statut = 'annulee'; return d; }
        if (user().role !== 'Admin tout') throw new Erreur(403, 'Seuls Simon et Mike approuvent une liste de prix');
        exiger(d.statut === 'recue', `Seule une liste reçue s'approuve (statut : ${d.statut})`);
        const jour = d.signe_le.slice(0, 10);
        let n = 0;
        for (const l of d.lignes.filter((x) => x.cout_cents)) {
          etat.tarifs = etat.tarifs.filter((x) => !(x.fournisseur_id === d.fournisseur_id && x.type_travail_id === l.type_travail_id));
          etat.tarifs.push({ fournisseur_id: d.fournisseur_id, type_travail_id: l.type_travail_id, cout_cents: l.cout_cents, en_vigueur_du: jour, valide_jusqu: d.valide_jusqu }); n++;
        }
        d.statut = 'approuvee'; d.approuvee_le = new Date(etat.maintenant).toISOString();
        return { tarifs: n };
      },
    },
    'prix-public': {
      GET: (_q, _b, entetes) => {
        const d = etat.demandes.find((x) => x.jeton === entetes['X-Jeton']);
        if (!d || d.statut === 'annulee') throw new Erreur(404, 'Lien invalide ou annulé. Communique avec Belleflamme.');
        d.ouverte_le ||= new Date(etat.maintenant).toISOString();
        return { statut: d.statut, message: d.message, expire_le: d.expire_le, fournisseur: etat.fournisseurs.find((f) => f.id === d.fournisseur_id)?.nom,
          signataire_nom: d.signataire_nom, signe_le: d.signe_le, valide_jusqu: d.valide_jusqu, categories: etat.categories, lignes: d.lignes };
      },
      POST: (_q, b, entetes) => {
        const d = etat.demandes.find((x) => x.jeton === entetes['X-Jeton']);
        if (!d || d.statut === 'annulee') throw new Erreur(404, 'Lien invalide ou annulé');
        exiger(d.statut === 'envoyee', 'Cette liste de prix a déjà été envoyée');
        exiger(String(b.nom || '').trim().length >= 3, 'Nom du signataire requis');
        exiger(String(b.signature || '').startsWith('data:image/png;base64,'), 'Signature requise');
        exiger(b.atteste === true, 'Il faut confirmer que les prix sont valides un an');
        for (const x of b.lignes || []) { const l = d.lignes.find((y) => y.id === x.id); if (l) Object.assign(l, { cout_cents: x.non_offert ? null : x.cout_cents, non_offert: !!x.non_offert, note: x.note || null }); }
        exiger(d.lignes.every((l) => l.cout_cents || l.non_offert), 'Chaque ligne doit avoir un prix ou être marquée « je n\'offre pas ce service »');
        const signe = new Date(etat.maintenant); const fin = new Date(signe); fin.setFullYear(fin.getFullYear() + 1);
        Object.assign(d, { statut: 'recue', signataire_nom: String(b.nom).trim(), signature_png: b.signature, signe_le: signe.toISOString(), valide_jusqu: fin.toISOString().slice(0, 10) });
        return { ok: true, signe_le: d.signe_le, valide_jusqu: d.valide_jusqu };
      },
    },
    'installation-options': { GET: () => ({ types: etat.types, categories: etat.categories, sousTraitants: etat.fournisseurs, confies: etat.confies, grille: etat.tarifs, margeBp: etat.margeBp }) },
    'installation-tarifs': {
      POST: (_q, b) => {
        if (user().role !== 'Admin tout') throw new Erreur(403, 'Modification refusée (Simon ou Mike seulement)');
        exiger(Number.isInteger(b.cout_cents) && b.cout_cents > 0, 'Coût en cents requis');
        const t = { en_vigueur_du: new Date().toISOString().slice(0, 10), ...b };
        etat.tarifs = etat.tarifs.filter((x) => !(x.fournisseur_id === t.fournisseur_id && x.type_travail_id === t.type_travail_id)); etat.tarifs.push(t); return t;
      },
      PATCH: (_q, b) => { etat.margeBp = Number(b.marge_bp); return { ok: true }; },
      PUT: (_q, b) => {
        const code = String(b.code || '').trim().toUpperCase();
        exiger(/^[A-Z0-9-]{3,40}$/.test(code), 'Code : lettres, chiffres et tirets (ex. INST-MURAL-1T-12)');
        exiger(!etat.types.some((t) => t.code === code), 'Ce code existe déjà');
        const t = { id: `t-${code}`, code, nom: b.nom, categorie: b.categorie, unite: b.unite || 'forfait', ordre: etat.types.length }; etat.types.push(t); return t;
      },
    },
  };

  window.__demoServeur = {
    etat, UTILISATEURS,
    changerUtilisateur: (qui) => { etat.qui = qui; },
    avancer: (min) => { etat.maintenant += min * M; },
    leadArrive: () => creerLead({}),
    heure: () => new Date(etat.maintenant),
    // Point d'entrée : (fonction, méthode, query, corps) -> { status, body }
    dernierLien: () => etat.dernierLien,
    appeler(fn, methode, query, corps, entetes = {}) {
      const r = routes[fn];
      try {
        if (!r) return { status: 404, body: { error: { code: 'demo', message: `« ${fn} » n'existe pas dans le HTML de test` } } };
        const h = typeof r === 'function' ? r : r[methode];
        if (!h) return { status: 405, body: { error: { code: 'methode', message: `Méthode ${methode} non permise` } } };
        const body = h(query, corps || {}, entetes);
        return { status: methode === 'POST' && ['leads', 'lead-activite', 'clients-create', 'sous-traitants', 'prix-demandes'].includes(fn) ? 201 : 200, body: JSON.parse(JSON.stringify(body ?? {})) };
      } catch (e) {
        return { status: e.status || 500, body: { error: { code: 'erreur', message: e.message } } };
      }
    },
  };
}());
