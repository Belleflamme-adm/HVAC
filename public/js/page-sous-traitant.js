// Fiche du sous-traitant (ADR-064) : la compagnie, le propriétaire et le responsable. Modifiable par la planification.
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
  ];
  const PERSONNES = [
    ['proprietaire_nom', 'Nom du propriétaire', {}],
    ['responsable_nom', 'Nom du responsable', {}],
    ['responsable_telephone', 'Téléphone du responsable', { type: 'tel' }],
    ['responsable_courriel', 'Courriel du responsable', { type: 'email' }],
  ];

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
      msg, form);
  }
  if (!id) remplir(zone, h('p', { class: 'bf-message bf-message--alerte' }, 'Sous-traitant non précisé.'));
  else charger();
}
