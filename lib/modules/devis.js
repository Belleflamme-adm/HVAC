// Module Devis. Les calculs (prix, rabais, plafonds, taxes, numéro, validité) sont faits par la base :
// ici on valide les entrées et on enchaîne les appels.
import { choisir, uuid, ErreurValidation } from '../handler.js';

const STATUTS_PERMIS = ['envoye', 'accepte', 'refuse', 'annule'];

export async function listerDevis(repo, { statut, client_id, vendeur_id, limite } = {}) {
  const filtre = {};
  if (statut === 'expire') { filtre.statut = 'envoye'; filtre.valide_jusqu = { op: 'lt', val: new Date().toISOString().slice(0, 10) }; }
  else if (statut) filtre.statut = statut;
  if (client_id) filtre.client_id = uuid(client_id, 'client_id');
  if (vendeur_id) filtre.vendeur_id = uuid(vendeur_id, 'vendeur_id');
  return repo.list('devis_v', {
    select: 'id,numero,statut,statut_effectif,succursale_code,client_id,client_prenom,client_nom,client_entreprise,'
      + 'vendeur_nom,total_cents,date_devis,valide_jusqu,approbations_en_attente,bloque_par_rabais',
    filtre, ordre: { colonne: 'created_at', asc: false }, limite: Number(limite) || 100,
  });
}

export async function obtenirDevis(repo, id) {
  uuid(id);
  const devis = await repo.get('devis_v', id);
  if (!devis) return null;
  const [lignes, approbations, client, site] = await Promise.all([
    repo.list('devis_lignes', { filtre: { devis_id: id }, ordre: { colonne: 'position' }, limite: 500 }),
    repo.list('approbations_rabais', { filtre: { devis_id: id }, ordre: { colonne: 'created_at' } }),
    repo.get('clients', devis.client_id),
    devis.site_id ? repo.get('sites', devis.site_id) : null,
  ]);
  return { devis, lignes, approbations, client, site };
}

export async function creerDevis(repo, data, token, corps) {
  const champs = choisir(corps, ['client_id', 'site_id', 'lead_id', 'inspection_id', 'mode_paiement', 'notes_client', 'notes_internes'], ['client_id']);
  uuid(champs.client_id, 'client_id');
  const client = await repo.get('clients', champs.client_id);
  if (!client) throw Object.assign(new Error('Client introuvable'), { status: 404, code: 'introuvable' });
  const { employe } = await data.session(token);
  if (!employe) throw Object.assign(new Error('Non connecté'), { status: 401, code: 'non_connecte' });
  return repo.insert('devis', { ...champs, succursale_code: client.succursale_code, vendeur_id: employe.id });
}

export async function modifierDevis(repo, id, corps) {
  uuid(id);
  const patch = choisir(corps, ['site_id', 'mode_paiement', 'depot_bp', 'notes_client', 'notes_internes']);
  if (!Object.keys(patch).length) throw new ErreurValidation('Aucun champ à modifier');
  return repo.update('devis', id, patch);
}

function verifierRabais(bp) {
  if (bp === undefined) return;
  if (!Number.isInteger(bp) || bp < 0 || bp > 10000) throw new ErreurValidation('Rabais invalide (points de base, 0 à 10000)');
}

export async function ajouterLigne(repo, corps) {
  const l = choisir(corps, ['devis_id', 'produit_id', 'kit_id', 'description', 'quantite', 'rabais_bp', 'prix_unitaire_cents', 'taxable', 'position']);
  uuid(l.devis_id, 'devis_id');
  if (l.produit_id && l.kit_id) throw new ErreurValidation('Un produit ou un kit, pas les deux');
  verifierRabais(l.rabais_bp);
  if (l.produit_id || l.kit_id) {
    const source = l.produit_id ? await repo.get('produits', uuid(l.produit_id, 'produit_id'))
                                : await repo.get('kits', uuid(l.kit_id, 'kit_id'));
    if (!source) throw Object.assign(new Error('Article introuvable'), { status: 404, code: 'introuvable' });
    l.description = l.description || source.nom;
    l.prix_unitaire_cents = 0;   // le prix réel est imposé par la base (catalogue)
    if (l.produit_id && source.taxable === false) l.taxable = false;
  } else {
    if (!l.description) throw new ErreurValidation('Description requise pour une ligne libre');
    if (!Number.isInteger(l.prix_unitaire_cents) || l.prix_unitaire_cents < 0) throw new ErreurValidation('Prix en cents requis');
  }
  if (l.position === undefined) {
    const lignes = await repo.list('devis_lignes', { select: 'position', filtre: { devis_id: l.devis_id }, limite: 500 });
    l.position = lignes.reduce((m, x) => Math.max(m, x.position), 0) + 1;
  }
  return repo.insert('devis_lignes', l);
}

export async function modifierLigne(repo, id, corps) {
  uuid(id);
  const patch = choisir(corps, ['description', 'quantite', 'rabais_bp', 'prix_unitaire_cents', 'taxable', 'position']);
  verifierRabais(patch.rabais_bp);
  return repo.update('devis_lignes', id, patch);
}

export async function retirerLigne(repo, id) {
  uuid(id);
  return repo.remove('devis_lignes', id);
}

export async function changerStatut(repo, corps) {
  const { id, statut } = choisir(corps, ['id', 'statut', 'raison_refus'], ['id', 'statut']);
  uuid(id);
  if (!STATUTS_PERMIS.includes(statut)) throw new ErreurValidation(`Statut non permis : ${statut}`);
  const patch = { statut };
  if (statut === 'refuse' && corps.raison_refus) patch.raison_refus = String(corps.raison_refus).slice(0, 500);
  return repo.update('devis', id, patch);
}

export async function renouveler(repo, id) {
  return { id: await repo.rpc('hvac_dupliquer_devis', { p_devis: uuid(id) }) };
}

export async function demanderApprobation(repo, corps) {
  const { devis_ligne_id, motif } = choisir(corps, ['devis_ligne_id', 'motif'], ['devis_ligne_id', 'motif']);
  uuid(devis_ligne_id, 'devis_ligne_id');
  // rabais, plafond et devis sont recopiés de la ligne par la base
  return repo.insert('approbations_rabais', { devis_ligne_id, motif: String(motif).slice(0, 1000) });
}

export async function deciderApprobation(repo, corps) {
  const { id, decision, commentaire } = choisir(corps, ['id', 'decision', 'commentaire'], ['id', 'decision']);
  uuid(id);
  if (!['approuvee', 'refusee'].includes(decision)) throw new ErreurValidation('Décision : approuvee ou refusee');
  return repo.update('approbations_rabais', id, { statut: decision, commentaire: commentaire ? String(commentaire).slice(0, 1000) : null });
}

export async function approbationsEnAttente(repo) {
  return repo.list('approbations_rabais', {
    select: 'id,created_at,rabais_bp,plafond_bp,motif,devis_id,'
      + 'devis(numero,succursale_code,client_id),devis_lignes(description,quantite,prix_unitaire_cents),'
      + 'demandeur:employes!approbations_rabais_demande_par_fkey(prenom,nom)',
    filtre: { statut: 'en_attente' }, ordre: { colonne: 'created_at' },
  });
}

// Catalogue : produits et kits actifs, prix du kit calculé si non fixé.
export async function chercherCatalogue(repo, q) {
  const terme = String(q || '').trim();
  if (terme.length < 2) return { produits: [], kits: [] };
  const [produits, kits] = await Promise.all([
    repo.list('produits', {
      select: 'id,sku,nom,categorie,modele,btu_nominal,prix_cents,marque_id,fictif',
      filtre: { actif: true }, recherche: { colonnes: ['nom', 'sku', 'modele'], terme }, ordre: { colonne: 'nom' }, limite: 30,
    }),
    repo.list('kits', {
      select: 'id,code,nom,prix_cents,fictif,kit_items(quantite,produits(prix_cents))',
      filtre: { actif: true }, recherche: { colonnes: ['nom', 'code'], terme }, ordre: { colonne: 'nom' }, limite: 15,
    }),
  ]);
  return {
    produits,
    kits: kits.map(({ kit_items: items = [], ...k }) => ({
      ...k,
      prix_cents: k.prix_cents ?? items.reduce((s, i) => s + Math.round(Number(i.quantite) * (i.produits?.prix_cents || 0)), 0),
    })),
  };
}
