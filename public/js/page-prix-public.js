// Liste de prix à remplir par le sous-traitant (ADR-061) : page publique, SANS compte.
// Le jeton vient du fragment (#) du lien et voyage dans l'en-tête X-Jeton (jamais dans l'adresse du serveur).
// Le sous-traitant donne un prix par ligne (ou « je n'offre pas ce service »), signe à l'écran, et atteste
// que ses prix sont valides un an complet à partir de la date du jour (date fixée par le serveur).
import { h, remplir } from './bf-dom.js?v=0.4.0';
import { formatCents } from './bf-money.js?v=0.4.0';

const UNITES = { forfait: 'forfait', tete: 'par tête', pied: 'par pied', sortie: 'par sortie', heure: 'par heure', unite: 'par unité', livre: 'par livre' };
const zone = document.getElementById('contenu');
const jeton = location.hash.slice(1);
const dateLongue = (d) => new Date(d).toLocaleDateString('fr-CA', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'America/Toronto' });
const dansUnAn = () => { const d = new Date(); d.setFullYear(d.getFullYear() + 1); return d; };
const enCents = (t) => {
  const n = Number(String(t).replace(',', '.').replace(/[\s$]/g, ''));
  return Number.isFinite(n) && n > 0 ? Math.round(n * 100) : null;
};

async function appel(methode, corps) {
  const r = await fetch('/.netlify/functions/prix-public', {
    method: methode, headers: { 'X-Jeton': jeton, ...(corps ? { 'Content-Type': 'application/json' } : {}) },
    body: corps ? JSON.stringify(corps) : undefined, referrerPolicy: 'no-referrer',
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(data?.error?.message || `Erreur ${r.status}`);
  return data;
}

// Pavé de signature (souris, doigt ou crayon)
function pave() {
  const canvas = h('canvas', { class: 'bf-pave', width: 600, height: 180, 'aria-label': 'Signe ici avec ta souris ou ton doigt' });
  const ctx = canvas.getContext('2d');
  let dessine = false; let vide = true;
  const pos = (e) => { const r = canvas.getBoundingClientRect(); return [(e.clientX - r.left) * canvas.width / r.width, (e.clientY - r.top) * canvas.height / r.height]; };
  const effacer = () => { ctx.fillStyle = '#ffffff'; ctx.fillRect(0, 0, canvas.width, canvas.height); vide = true; };
  effacer();
  ctx.lineWidth = 2.6; ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.strokeStyle = '#14201a';
  canvas.addEventListener('pointerdown', (e) => { dessine = true; canvas.setPointerCapture(e.pointerId); ctx.beginPath(); ctx.moveTo(...pos(e)); });
  canvas.addEventListener('pointermove', (e) => { if (!dessine) return; ctx.lineTo(...pos(e)); ctx.stroke(); vide = false; });
  const fin = () => { dessine = false; };
  canvas.addEventListener('pointerup', fin); canvas.addEventListener('pointercancel', fin);
  return { canvas, effacer, estVide: () => vide, png: () => canvas.toDataURL('image/png') };
}

function rendreRecu(d, titre) {
  remplir(zone,
    h('h1', {}, titre),
    h('section', { class: 'bf-carte-section bf-demande-ok' },
      h('p', {}, `Merci ${d.signataire_nom || ''}. Belleflamme a bien reçu ta liste de prix, signée le ${dateLongue(d.signe_le)}.`),
      h('p', {}, h('strong', {}, `Tes prix sont valides jusqu'au ${dateLongue(d.valide_jusqu)}.`)),
      h('p', { class: 'bf-muet' }, 'Le lien ne peut plus être modifié. Pour un changement, communique avec Belleflamme.')),
    d.lignes ? h('div', { class: 'bf-table-zone' }, h('table', { class: 'bf-table' },
      h('thead', {}, h('tr', {}, ['Travail', 'Unité', 'Ton prix'].map((t) => h('th', {}, t)))),
      h('tbody', {}, d.lignes.map((l) => h('tr', {}, h('td', {}, h('strong', {}, l.code), ` | ${l.nom}`), h('td', {}, UNITES[l.unite] || l.unite),
        h('td', { class: 'num' }, l.non_offert ? 'Non offert' : formatCents(l.cout_cents))))))) : null);
}

async function demarrer() {
  if (!/^[0-9a-f]{64}$/.test(jeton)) {
    remplir(zone, h('h1', {}, 'Lien incomplet'), h('p', {}, 'Ce lien de liste de prix est incomplet. Ouvre le lien exact reçu de Belleflamme, ou demande-lui un nouveau lien.'));
    return;
  }
  let d;
  try { d = await appel('GET'); } catch (e) { remplir(zone, h('h1', {}, 'Liste de prix'), h('p', { class: 'bf-message bf-message--erreur' }, e.message)); return; }
  if (d.statut !== 'envoyee') { rendreRecu(d, 'Liste de prix déjà envoyée'); return; }

  const msg = h('p', { class: 'bf-message', role: 'alert' });
  const saisies = [];
  const nomsCat = Object.fromEntries((d.categories || []).map((c) => [c.code, c.nom]));
  const parCat = new Map();
  for (const l of d.lignes) { if (!parCat.has(l.categorie)) parCat.set(l.categorie, []); parCat.get(l.categorie).push(l); }
  const compte = h('span', { class: 'bf-muet' });
  const majCompte = () => { const n = saisies.filter((s) => s.non.checked || enCents(s.champ.value)).length; compte.textContent = `${n} sur ${saisies.length} lignes remplies`; };

  const sections = [...parCat.entries()].map(([cat, ls]) => h('section', { class: 'bf-prix-section' },
    h('h2', { class: 'bf-prix-section__titre' }, nomsCat[cat] || 'Autres travaux'),
    ls.map((l) => {
      const champ = h('input', { class: 'bf-prix__champ', inputmode: 'decimal', placeholder: 'Ton prix $', 'aria-label': `Ton prix : ${l.nom}` });
      const non = h('input', { type: 'checkbox', 'aria-label': `Je n'offre pas ce service : ${l.nom}` });
      const note = h('input', { class: 'bf-prix__note', placeholder: 'Note (optionnel)', maxlength: 300, 'aria-label': `Note : ${l.nom}` });
      non.addEventListener('change', () => { champ.disabled = non.checked; if (non.checked) champ.value = ''; majCompte(); });
      champ.addEventListener('input', majCompte);
      saisies.push({ l, champ, non, note });
      return h('div', { class: 'bf-prix bf-prix--public' },
        h('div', { class: 'bf-prix__texte' }, h('div', {}, h('strong', {}, l.code), ` | ${l.nom}`),
          l.description ? h('div', { class: 'bf-prix__inclus' }, `Inclus : ${l.description}`) : null, note),
        h('div', { class: 'bf-prix__droite' },
          h('label', { class: 'bf-prix__saisie' }, champ, h('span', { class: 'bf-prix__unite' }, UNITES[l.unite] || l.unite)),
          h('label', { class: 'bf-case bf-muet' }, non, 'Je n\'offre pas ce service')));
    })));

  const signature = pave();
  const nom = h('input', { id: 'nom-signataire', autocomplete: 'name', placeholder: 'Prénom et nom', required: true });
  const echeance = dansUnAn();
  const atteste = h('input', { type: 'checkbox', id: 'atteste', required: true });
  const envoyer = h('button', { class: 'bf-bouton', type: 'submit' }, 'Signer et envoyer à Belleflamme');
  const form = h('form', { class: 'bf-form', novalidate: true },
    h('h2', {}, 'Signature'),
    h('label', { for: 'nom-signataire' }, 'Nom du signataire', nom),
    h('div', {}, h('span', { class: 'bf-muet' }, 'Signe dans le cadre :'), signature.canvas,
      h('button', { class: 'bf-lien', type: 'button', onclick: () => signature.effacer() }, 'Effacer la signature')),
    h('p', {}, `Date : ${dateLongue(new Date())} (inscrite par le serveur au moment de l'envoi)`),
    h('label', { class: 'bf-case bf-attestation' }, atteste,
      `Je confirme que les prix ci-dessus sont valides pour une période d'un an complète à partir d'aujourd'hui, soit jusqu'au ${dateLongue(echeance)}.`),
    msg, h('div', { class: 'bf-actions' }, envoyer, compte));

  form.addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const manquantes = saisies.filter((s) => !s.non.checked && !enCents(s.champ.value));
    if (manquantes.length) { msg.textContent = `Il manque ${manquantes.length} prix. Inscris un prix ou coche « Je n'offre pas ce service ».`; manquantes[0].champ.focus(); return; }
    if (nom.value.trim().length < 3) { msg.textContent = 'Inscris ton nom.'; nom.focus(); return; }
    if (signature.estVide()) { msg.textContent = 'Signe dans le cadre.'; return; }
    if (!atteste.checked) { msg.textContent = 'Coche la confirmation de validité d\'un an.'; return; }
    envoyer.disabled = true; envoyer.textContent = 'Envoi…';
    try {
      const r = await appel('POST', {
        lignes: saisies.map((s) => ({ id: s.l.id, cout_cents: s.non.checked ? null : enCents(s.champ.value), non_offert: s.non.checked, note: s.note.value.trim() || undefined })),
        nom: nom.value.trim(), signature: signature.png(), atteste: true,
      });
      rendreRecu({ ...r, signataire_nom: nom.value.trim(), lignes: saisies.map((s) => ({ ...s.l, non_offert: s.non.checked, cout_cents: enCents(s.champ.value) })) }, 'Liste de prix envoyée');
      window.scrollTo(0, 0);
    } catch (e) { msg.textContent = e.message; envoyer.disabled = false; envoyer.textContent = 'Signer et envoyer à Belleflamme'; }
  });

  remplir(zone,
    h('h1', {}, `Liste de prix | ${d.fournisseur}`),
    h('p', {}, 'Belleflamme te demande ton prix pour les travaux ci-dessous. Inscris ton prix pour chaque ligne, ou coche « Je n\'offre pas ce service ». Les prix sont avant taxes.'),
    d.message ? h('p', { class: 'bf-message bf-message--alerte' }, `Message de Belleflamme : ${d.message}`) : null,
    h('p', { class: 'bf-muet' }, `Ce lien est valide jusqu'au ${dateLongue(d.expire_le)} et ne sert qu'une fois.`),
    sections, form);
  majCompte();
}
demarrer();
