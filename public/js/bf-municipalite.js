// Champ « municipalité » : recherche dans la liste officielle et retient le code.
import { api } from './bf-api.js?v=0.4.0';
import { h } from './bf-dom.js?v=0.4.0';

let compteur = 0;
export function champMunicipalite({ requis = false } = {}) {
  const id = `muni-${compteur += 1}`;
  const liste = h('datalist', { id });
  const input = h('input', { list: id, required: requis, autocomplete: 'off', placeholder: 'Ville (municipalité)', 'aria-label': 'Municipalité' });
  let resultats = [];
  let choisi = null;
  let minuterie;
  input.addEventListener('input', () => {
    choisi = resultats.find((m) => m.nom === input.value) || null;
    clearTimeout(minuterie);
    minuterie = setTimeout(async () => {
      if (input.value.trim().length < 2) return;
      try {
        resultats = await api.get('municipalites', { q: input.value.trim() });
        liste.replaceChildren(...resultats.map((m) => h('option', { value: m.nom }, [m.mrc, m.region].filter(Boolean).join(' | '))));
        choisi = resultats.find((m) => m.nom === input.value) || choisi;
      } catch { /* liste non disponible : saisie libre */ }
    }, 200);
  });
  return {
    el: h('span', { class: 'bf-champ-muni' }, input, liste),
    input,
    // { municipalite_code, ville } ; sans correspondance officielle : ville saisie, code absent
    valeur: () => ({ municipalite_code: choisi?.code, ville: (choisi?.nom || input.value).trim() }),
  };
}
