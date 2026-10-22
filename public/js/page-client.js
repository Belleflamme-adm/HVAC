import { initPage } from './bf-page.js?v=0.3.0';
import { api } from './bf-api.js?v=0.3.0';
import { remplir, h, message, param, dateFr, pastilleStatut } from './bf-dom.js?v=0.3.0';
import { formatCents } from './bf-money.js?v=0.3.0';

const user = await initPage();
if (user) {
  const zone = document.getElementById('contenu');
  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const id = param('id');

  async function charger() {
    let d;
    try { d = await api.get('clients-get', { id }); } catch (e) { remplir(zone, msg); message(msg, e.message); return; }
    const { client: c, sites, devis } = d;
    const nom = [c.prenom, c.nom].filter(Boolean).join(' ') || c.entreprise;

    const nouveauDevis = async (siteId) => {
      try {
        const dv = await api.post('devis-create', { client_id: c.id, site_id: siteId || sites[0]?.id });
        location.href = `/devis-edition?id=${dv.id}`;
      } catch (e) { message(msg, e.message); }
    };

    const formSite = h('form', { class: 'bf-form', hidden: true },
      h('div', { class: 'bf-grille2' },
        h('label', {}, 'Adresse *', h('input', { name: 'adresse', required: true })),
        h('label', {}, 'Ville *', h('input', { name: 'ville', required: true })),
        h('label', {}, 'Code postal', h('input', { name: 'code_postal' })),
        h('label', {}, 'Type', h('select', { name: 'type_habitation' }, ['', 'maison', 'condo', 'multiplex', 'immeuble', 'commercial', 'autre'].map((t) => h('option', { value: t }, t || '(choisir)'))))),
      h('label', { class: 'bf-case' }, h('input', { type: 'checkbox', name: 'a_geothermie' }), 'Système géothermique présent'),
      h('button', { class: 'bf-bouton', type: 'submit' }, 'Ajouter le lieu'));
    formSite.addEventListener('submit', async (ev) => {
      ev.preventDefault();
      const f = new FormData(formSite);
      try {
        await api.post('sites-save', { client_id: c.id, adresse: f.get('adresse'), ville: f.get('ville'),
          code_postal: f.get('code_postal') || undefined, type_habitation: f.get('type_habitation') || undefined,
          a_geothermie: f.get('a_geothermie') === 'on' });
        charger();
      } catch (e) { message(msg, e.message); }
    });

    const avertissements = [];
    if (c.est_proprietaire === false) avertissements.push('Locataire : non admissible à LogisVert pour une thermopompe.');
    if (c.est_proprietaire && !c.nom_preuve_propriete) avertissements.push('Nom de la preuve de propriété manquant (exigé par LogisVert).');

    remplir(zone, 
      h('p', {}, h('a', { href: '/clients' }, '← Clients')),
      h('div', { class: 'bf-titre' }, h('h1', {}, nom), h('button', { class: 'bf-bouton', type: 'button', onclick: () => nouveauDevis() }, 'Nouveau devis')),
      msg,
      ...avertissements.map((a) => h('p', { class: 'bf-message bf-message--alerte' }, a)),
      h('section', { class: 'bf-carte-section' }, h('h2', {}, 'Coordonnées'),
        h('dl', { class: 'bf-dl' },
          h('dt', {}, 'Téléphone'), h('dd', {}, c.telephone || 'Non indiqué'),
          h('dt', {}, 'Courriel'), h('dd', {}, c.courriel || 'Non indiqué'),
          h('dt', {}, 'Succursale'), h('dd', {}, c.succursale_code),
          h('dt', {}, 'Propriétaire'), h('dd', {}, c.est_proprietaire === null ? 'À confirmer' : c.est_proprietaire ? 'Oui' : 'Non'),
          h('dt', {}, 'Preuve de propriété'), h('dd', {}, c.nom_preuve_propriete || 'Non indiqué'),
          h('dt', {}, 'Exemption de taxes'), h('dd', {}, c.exemption_taxes === 'aucune' ? 'Aucune' : c.exemption_taxes))),
      h('section', { class: 'bf-carte-section' },
        h('div', { class: 'bf-titre' }, h('h2', {}, 'Lieux d\'installation'),
          h('button', { class: 'bf-bouton bf-bouton--discret', type: 'button', onclick: () => { formSite.hidden = !formSite.hidden; } }, 'Ajouter')),
        sites.length ? h('ul', { class: 'bf-simple' }, sites.map((s) => h('li', {},
          `${s.adresse}, ${s.ville} ${s.code_postal || ''}`, s.a_geothermie ? h('span', { class: 'bf-muet' }, ' | géothermie') : null,
          ' ', h('button', { class: 'bf-lien', type: 'button', onclick: () => nouveauDevis(s.id) }, 'Devis pour ce lieu'))))
          : h('p', { class: 'bf-muet' }, 'Aucun lieu.'),
        formSite),
      h('section', { class: 'bf-carte-section' }, h('h2', {}, 'Devis'),
        devis.length ? h('div', { class: 'bf-liste' }, devis.map((dv) => h('a', { class: 'bf-ligne', href: `/devis-edition?id=${dv.id}` },
          h('strong', {}, `#${dv.numero}`), pastilleStatut(dv.statut_effectif),
          h('span', {}, formatCents(dv.total_cents)), h('span', { class: 'bf-muet' }, dateFr(dv.date_devis)))))
          : h('p', { class: 'bf-muet' }, 'Aucun devis.')));
  }
  charger();
}
