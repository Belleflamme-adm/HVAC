// Gestion des sous-traitants (planification : Simon, Mike, coordination).
import { initPage } from './bf-page.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message } from './bf-dom.js?v=0.4.0';

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const liste = h('div', { class: 'bf-liste' });
  const planif = ['Admin tout', 'Direction', 'Coordonnateur'].includes(user.role);

  async function charger() {
    try {
      const sts = await api.get('sous-traitants');
      remplir(liste, ...(sts.length ? sts.map((s) => h('div', { class: 'bf-ligne' },
        h('strong', {}, s.nom), h('span', { class: 'bf-muet' }, [s.telephone, s.courriel, s.licence_rbq ? `RBQ ${s.licence_rbq}` : null].filter(Boolean).join(' | ')),
        h('span', { class: 'bf-actions' },
          h('a', { class: 'bf-bouton bf-bouton--discret', href: `/territoire?fournisseur=${s.id}` }, 'Territoire'),
          h('a', { class: 'bf-bouton bf-bouton--discret', href: `/disponibilites?fournisseur=${s.id}` }, 'Disponibilités'))))
        : [h('p', { class: 'bf-muet' }, 'Aucun sous-traitant.')]));
    } catch (e) { message(msg, e.message); }
  }

  const champ = (label, nom, attrs = {}) => h('label', {}, label, h('input', { name: nom, ...attrs }));
  const form = h('form', { class: 'bf-form', hidden: true },
    h('h2', {}, 'Nouveau sous-traitant'),
    h('div', { class: 'bf-grille2' },
      champ('Entreprise *', 'nom', { required: true }), champ('Téléphone', 'telephone', { type: 'tel' }),
      champ('Courriel de l\'entreprise', 'courriel', { type: 'email' }), champ('Licence RBQ', 'licence_rbq'),
      champ('Prénom du contact *', 'prenom', { required: true }), champ('Nom du contact *', 'contact_nom', { required: true }),
      champ('Courriel de connexion *', 'email', { type: 'email', required: true })),
    h('p', { class: 'bf-muet' }, 'Le contact recevra un accès limité : son territoire, ses disponibilités et, plus tard, ses jobs. '
      + 'Avant l\'accès, faire signer une entente de confidentialité (Loi 25). L\'invitation se fait dans Supabase Auth (même courriel).'),
    h('div', { class: 'bf-actions' },
      h('button', { class: 'bf-bouton', type: 'submit' }, 'Créer'),
      h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => { form.hidden = true; } }, 'Annuler')));
  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const f = new FormData(form);
    const v = (k) => (f.get(k) || '').toString().trim() || undefined;
    try {
      await api.post('sous-traitants', { nom: v('nom'), telephone: v('telephone'), courriel: v('courriel'), licence_rbq: v('licence_rbq'),
        contact: { prenom: v('prenom'), nom: v('contact_nom'), email: v('email') } });
      form.reset(); form.hidden = true; message(msg, 'Sous-traitant créé.', 'ok'); charger();
    } catch (e) { message(msg, e.message); }
  });

  remplir(zone,
    h('div', { class: 'bf-titre' }, h('h1', {}, 'Sous-traitants'),
      planif ? h('button', { class: 'bf-bouton', type: 'button', onclick: () => { form.hidden = false; } }, 'Nouveau sous-traitant') : null),
    h('p', {}, h('a', { href: '/territoire' }, 'Carte des territoires et des sous-traitants principaux')),
    msg, form, liste);
  charger();
}
