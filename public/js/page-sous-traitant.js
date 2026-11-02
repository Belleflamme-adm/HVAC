// Fiche du sous-traitant (ADR-064) : la compagnie, le propriétaire et le responsable. Modifiable par la planification.
// Accès (ADR-095) : un compte, au courriel du responsable, connexion par code reçu par courriel ; envoyer, couper, rétablir.
import { initPage } from './bf-page.js?v=0.4.0';
import { api } from './bf-api.js?v=0.4.0';
import { remplir, h, message, param } from './bf-dom.js?v=0.4.0';

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const id = param('id');
  const planif = ['Admin tout', 'Direction', 'Coordonnateur'].includes(user.role);

  // [champ, libellé, attributs]
  const COMPAGNIE = [
    ['nom', 'Nom de la compagnie *', { required: true, autocomplete: 'organization' }],
    ['licence_rbq', 'Licence RBQ', { placeholder: '1234-5678-90', inputmode: 'numeric' }],
    ['neq', 'NEQ', { inputmode: 'numeric' }],
    ['telephone', 'Téléphone de la compagnie', { type: 'tel' }],
    ['courriel', 'Courriel de la compagnie', { type: 'email' }],
    ['adresse', 'Adresse', {}],
    ['partenaire_depuis', 'Partenaire Belleflamme depuis', { type: 'date' }],
  ];
  const PERSONNES = [
    ['proprietaire_nom', 'Nom du propriétaire', {}],
    ['responsable_nom', 'Nom du responsable', {}],
    ['responsable_telephone', 'Téléphone du responsable', { type: 'tel' }],
    ['responsable_courriel', 'Courriel du responsable', { type: 'email' }],
  ];

  const quand = (d) => new Date(d).toLocaleString('fr-CA', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });

  // Section Accès : seulement pour la planification
  async function sectionAcces(f) {
    let a;
    try { a = await api.get('sous-traitant', { id, vue: 'acces' }); }
    catch (e) { return h('section', { class: 'bf-carte-section' }, h('h2', {}, 'Accès à l\'app'), h('p', { class: 'bf-muet' }, e.message)); }
    const geste = async (action, question, ok) => {
      if (question && !confirm(question)) return;
      try { await api.post('sous-traitant', { action }, { id }); await charger(); message(msg, ok, 'ok'); } catch (e) { message(msg, e.message); }
    };
    const etat = !a.actif ? h('span', { class: 'bf-pastille bf-extra--refuse' }, 'Accès coupé')
      : a.connecte ? h('span', { class: 'bf-pastille bf-extra--approuve' }, 'Accès actif')
      : a.acces_envoye_le ? h('span', { class: 'bf-pastille' }, 'Code envoyé, pas encore connecté')
      : h('span', { class: 'bf-pastille' }, 'Accès jamais envoyé');
    return h('section', { class: 'bf-carte-section bf-acces' },
      h('div', { class: 'bf-dossier__tete' }, h('h2', {}, 'Accès à l\'app'), etat),
      h('p', {}, 'Un seul compte, au courriel du responsable : ', h('strong', {}, a.email), '. Il se connecte avec ce courriel et un code à 6 chiffres reçu par courriel, puis voit seulement ses jobs, sa liste de prix et ses extras.'),
      h('ul', { class: 'bf-simple bf-muet' },
        a.acces_envoye_le ? h('li', {}, `Dernier envoi : ${quand(a.acces_envoye_le)}`) : null,
        a.acces_coupe_le ? h('li', {}, `Coupé le ${quand(a.acces_coupe_le)}`) : null,
        h('li', {}, 'Pour changer de responsable : modifie « Courriel du responsable » plus haut. Le compte suit le nouveau courriel et l\'ancienne personne n\'entre plus.')),
      h('div', { class: 'bf-actions' },
        a.actif ? h('button', { type: 'button', class: 'bf-bouton', disabled: f.actif === false,
          onclick: () => geste('envoyer', null, `Code envoyé à ${a.email}.`) }, a.acces_envoye_le ? 'Renvoyer un code' : 'Envoyer l\'accès') : null,
        a.actif ? h('button', { type: 'button', class: 'bf-bouton bf-bouton--danger',
          onclick: () => geste('couper', `Couper l'accès de ${f.nom} ? Il ne pourra plus rien voir, tout de suite.`, 'Accès coupé.') }, 'Couper l\'accès')
          : h('button', { type: 'button', class: 'bf-bouton', disabled: f.actif === false,
            onclick: () => geste('retablir', null, 'Accès rétabli. Envoie-lui un code pour qu\'il se reconnecte.') }, 'Rétablir l\'accès')),
      f.actif === false ? h('p', { class: 'bf-muet' }, 'Sous-traitant inactif : son accès est coupé. Réactive-le pour rétablir l\'accès.') : null);
  }

  async function charger() {
    let f;
    try { f = await api.get('sous-traitant', { id }); } catch (e) { remplir(zone, msg); message(msg, e.message); return; }
    const depart = { ...f };
    const champ = ([nom, libelle, attrs]) => h('label', {}, libelle,
      h('input', { name: nom, value: f[nom] || '', disabled: !planif, ...attrs }));
    const actif = h('input', { type: 'checkbox', name: 'actif', checked: f.actif !== false, disabled: !planif });
    const enregistrer = h('button', { class: 'bf-bouton', type: 'submit', disabled: true }, 'Enregistrer');
    const form = h('form', { class: 'bf-form' },
      h('h2', {}, 'La compagnie'), h('div', { class: 'bf-grille2' }, COMPAGNIE.map(champ)),
      h('h2', {}, 'Propriétaire et responsable'), h('div', { class: 'bf-grille2' }, PERSONNES.map(champ)),
      h('label', { class: 'bf-case' }, actif, 'Sous-traitant actif (décoché : on ne lui confie plus de travaux)'),
      planif ? h('div', { class: 'bf-actions' }, enregistrer,
        h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => charger() }, 'Annuler les changements')) : null,
      h('p', { class: 'bf-muet' }, 'Renseignements personnels (Loi 25) : chaque modification est journalisée.'));

    // Seulement les champs modifiés partent au serveur
    const changements = () => {
      const d = new FormData(form); const c = {};
      for (const [nom] of [...COMPAGNIE, ...PERSONNES]) {
        const v = String(d.get(nom) || '').trim();
        if (v !== (depart[nom] || '')) c[nom] = v;
      }
      if (actif.checked !== (depart.actif !== false)) c.actif = actif.checked;
      return c;
    };
    form.addEventListener('input', () => { enregistrer.disabled = !Object.keys(changements()).length; });
    form.addEventListener('submit', async (ev) => {
      ev.preventDefault();
      const c = changements();
      if (!Object.keys(c).length) return;
      try {
        await api.patch('sous-traitant', c, { id });
        await charger();
        message(msg, 'Fiche enregistrée.', 'ok');
      } catch (e) { message(msg, e.message); }
    });

    remplir(zone,
      h('p', {}, h('a', { href: '/sous-traitants' }, '← Sous-traitants')),
      h('div', { class: 'bf-titre' }, h('h1', {}, f.nom),
        f.actif === false ? h('span', { class: 'bf-pastille' }, 'Inactif') : null),
      h('div', { class: 'bf-actions' },
        h('a', { class: 'bf-bouton bf-bouton--discret', href: `/territoire?fournisseur=${f.id}` }, 'Territoire'),
        h('a', { class: 'bf-bouton bf-bouton--discret', href: `/disponibilites?fournisseur=${f.id}` }, 'Disponibilités'),
        h('a', { class: 'bf-bouton bf-bouton--discret', href: `/mes-prix?fournisseur=${f.id}` }, 'Liste de prix et soumissions actives')),
      msg, form, planif ? await sectionAcces(f) : null);
  }
  if (!id) remplir(zone, h('p', { class: 'bf-message bf-message--alerte' }, 'Sous-traitant non précisé.'));
  else charger();
}
