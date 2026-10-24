import { test } from 'node:test';
import assert from 'node:assert/strict';
import { VENDEURS, parOrdreCreation } from '../../public/js/bf-ventes-fictives.js';

// ADR-077 : les vendeurs s'affichent toujours dans leur ordre de création, jamais classés par résultat
test('vendeurs : ordre de création unique et stable', () => {
  const numeros = Object.values(VENDEURS).map((v) => v.numero);
  assert.equal(new Set(numeros).size, numeros.length, 'un numéro par vendeur');
  const tries = Object.keys(VENDEURS).sort(parOrdreCreation);
  assert.deepEqual(tries.map((id) => VENDEURS[id].numero), [...numeros].sort((a, b) => a - b));
  assert.deepEqual([...tries].reverse().sort(parOrdreCreation), tries, 'le tri ne dépend pas de l\'ordre de départ');
});
