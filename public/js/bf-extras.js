// Feuille d'extra (ADR-081) : libellés partagés par « Mes jobs » (sous-traitant) et la file d'approbation (Belleflamme).
import { h } from './bf-dom.js?v=0.4.0';

export const CAUSES = { oubli_vendeur: 'Oubli du vendeur', imprevu_chantier: 'Imprévu de chantier', demande_client: 'Demande du client', autre: 'Autre' };
export const STATUTS_EXTRA = { brouillon: 'Brouillon', soumis: 'En attente d\'approbation', approuve: 'Approuvé', refuse: 'Refusé' };
export const pastilleExtra = (s) => h('span', { class: `bf-pastille bf-extra--${s}` }, STATUTS_EXTRA[s] || s);
export const marqueHorsListe = () => h('span', { class: 'bf-pastille bf-extra--hors', title: 'Prix proposé par le sous-traitant, absent de sa liste' }, 'Hors liste');
