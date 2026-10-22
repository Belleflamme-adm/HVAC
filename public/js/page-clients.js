import { initPage } from './bf-page.js?v=0.3.0';
import { api } from './bf-api.js?v=0.3.0';
import { remplir, h, message } from './bf-dom.js?v=0.3.0';
import { SUCCURSALES } from './bf-project-code.js?v=0.3.0';

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const liste = h('div', { class: 'bf-liste' });
  const recherche = h('input', { type: 'search', placeholder: 'Nom, téléphone, courriel…', 'aria-label': 'Rechercher un client' });

  async function charger() {
    try {
      const clients = await api.get('clients-list', { q: recherche.value.trim() });
      liste.replaceChildren(...(clients.length ? clients.map((c) => h('a', { class: 'bf-ligne', href: `/client?id=${c.id}` },
        h('strong', {}, [c.prenom, c.nom].filter(Boolean).join(' ') || c.entreprise),
        h('span', { class: 'bf-muet' }, [c.telephone, c.courriel, c.succursale_code].filter(Boolean).join(' | ')))) : [h('p', { class: 'bf-muet' }, 'Aucun client trouvé.')]));
    } catch (e) { message(msg, e.message); }
  }
  let minuterie;
  recherche.addEventListener('input', () => { clearTimeout(minuterie); minuterie = setTimeout(charger, 250); });

  // Création
  const champ = (label, nom, attrs = {}) => h('label', {}, label, h('input', { name: nom, ...attrs }));
  const form = h('form', { class: 'bf-form', hidden: true },
    h('h2', {}, 'Nouveau client'),
    h('div', { class: 'bf-grille2' },
      champ('Prénom', 'prenom'), champ('Nom *', 'nom', { required: true }),
      champ('Téléphone', 'telephone', { type: 'tel' }), champ('Courriel', 'courriel', { type: 'email' }),
      h('label', {}, 'Succursale *', h('select', { name: 'succursale_code', required: true },
        Object.entries(SUCCURSALES).map(([code, nom]) => h('option', { value: code, selected: code === user.succursale }, `${code} | ${nom}`)))),
      champ('Adresse d\'installation', 'adresse'), champ('Ville', 'ville'), champ('Code postal', 'code_postal')),
    h('label', { class: 'bf-case' }, h('input', { type: 'checkbox', name: 'est_proprietaire' }), 'Le client est propriétaire (LogisVert)'),
    champ('Nom sur la preuve de propriété (compte de taxes ou acte de vente)', 'nom_preuve_propriete'),
    h('label', { class: 'bf-case' }, h('input', { type: 'checkbox', name: 'consentement_comm' }), 'Le client accepte de recevoir nos communications'),
    h('div', { class: 'bf-actions' },
      h('button', { class: 'bf-bouton', type: 'submit' }, 'Créer le client'),
      h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => { form.hidden = true; } }, 'Annuler')));

  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const f = new FormData(form);
    const v = (k) => (f.get(k) || '').toString().trim() || undefined;
    try {
      const client = await api.post('clients-create', {
        prenom: v('prenom'), nom: v('nom'), telephone: v('telephone'), courriel: v('courriel'),
        succursale_code: v('succursale_code'), vendeur_id: user.id,
        est_proprietaire: f.get('est_proprietaire') === 'on', nom_preuve_propriete: v('nom_preuve_propriete'),
        consentement_comm: f.get('consentement_comm') === 'on',
        site: v('adresse') ? { adresse: v('adresse'), ville: v('ville') || '', code_postal: v('code_postal') } : undefined,
      });
      location.href = `/client?id=${client.id}`;
    } catch (e) { message(msg, e.message); }
  });

  remplir(zone, 
    h('div', { class: 'bf-titre' }, h('h1', {}, 'Clients'),
      h('button', { class: 'bf-bouton', type: 'button', onclick: () => { form.hidden = false; form.querySelector('[name=nom]').focus(); } }, 'Nouveau client')),
    recherche, msg, form, liste);
  charger();
}
