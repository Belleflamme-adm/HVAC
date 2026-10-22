// Module Clients : règles côté fonction (la base applique RLS et contraintes).
import { choisir, uuid, ErreurValidation } from '../handler.js';

const CHAMPS_CLIENT = ['type', 'prenom', 'nom', 'entreprise', 'courriel', 'telephone', 'langue', 'succursale_code',
  'vendeur_id', 'est_proprietaire', 'nom_preuve_propriete', 'hq_numero_client', 'hq_numero_compteur',
  'exemption_taxes', 'exemption_tps', 'exemption_tvq', 'exemption_numero', 'notes'];
const CHAMPS_SITE = ['libelle', 'adresse', 'ville', 'municipalite_code', 'province', 'code_postal', 'type_habitation',
  'annee_construction', 'a_geothermie', 'notes'];
const LISTE = 'id,type,prenom,nom,entreprise,courriel,telephone,succursale_code,vendeur_id,est_proprietaire';

// Consentement Loi 25 : les numéros Hydro-Québec exigent un consentement explicite, horodaté par la base.
function consentementHq(corps, ligne) {
  if (ligne.hq_numero_client || ligne.hq_numero_compteur) {
    if (corps.consentement_hq !== true) {
      throw new ErreurValidation('Consentement du client requis pour conserver ses numéros Hydro-Québec');
    }
    ligne.consentement_hq_le = new Date().toISOString();
  }
  if (corps.consentement_comm === true) ligne.consentement_comm_le = new Date().toISOString();
  return ligne;
}

export async function listerClients(repo, { q, succursale, limite } = {}) {
  const filtre = { actif: true };
  if (succursale) filtre.succursale_code = succursale;
  return repo.list('clients', {
    select: LISTE, filtre, ordre: { colonne: 'nom' }, limite: Number(limite) || 50,
    recherche: q ? { colonnes: ['nom', 'prenom', 'entreprise', 'courriel', 'telephone'], terme: q } : undefined,
  });
}

export async function obtenirClient(repo, id) {
  uuid(id);
  const client = await repo.get('clients', id);
  if (!client) return null;
  const [sites, devis] = await Promise.all([
    repo.list('sites', { filtre: { client_id: id }, ordre: { colonne: 'created_at' } }),
    repo.list('devis_v', {
      select: 'id,numero,code_projet,statut,statut_effectif,total_cents,date_devis,valide_jusqu,vendeur_nom',
      filtre: { client_id: id }, ordre: { colonne: 'created_at', asc: false },
    }),
  ]);
  return { client, sites, devis };
}

export async function creerClient(repo, corps) {
  const ligne = consentementHq(corps, choisir(corps, CHAMPS_CLIENT, ['nom', 'succursale_code']));
  const client = await repo.insert('clients', ligne);
  if (corps.site?.adresse) {
    await repo.insert('sites', { ...choisir(corps.site, CHAMPS_SITE, ['adresse', 'ville']), client_id: client.id });
  }
  return client;
}

export async function modifierClient(repo, id, corps) {
  uuid(id);
  const patch = consentementHq(corps, choisir(corps, CHAMPS_CLIENT.filter((c) => c !== 'succursale_code')));
  if (!Object.keys(patch).length) throw new ErreurValidation('Aucun champ à modifier');
  return repo.update('clients', id, patch);
}

export async function creerSite(repo, corps) {
  return repo.insert('sites', { ...choisir(corps, CHAMPS_SITE, ['adresse', 'ville']), client_id: uuid(corps.client_id, 'client_id') });
}

export async function modifierSite(repo, id, corps) {
  uuid(id);
  return repo.update('sites', id, choisir(corps, CHAMPS_SITE));
}
