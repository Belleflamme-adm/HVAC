import { test } from 'node:test';
import assert from 'node:assert/strict';
import { taxes, arrondiTaxe, montantLigne, plafondRabaisBp, formatCents } from '../../public/js/bf-money.js';

// Mêmes cas que tests/sql/10_phase1.test.sql : le JS et la base doivent arrondir pareil.
test('taxes identiques à app.taxes()', () => {
  assert.deepEqual(taxes(10000), { tps: 500, tvq: 998, total: 11498 });
  assert.deepEqual(taxes(1), { tps: 0, tvq: 0, total: 1 });
  assert.deepEqual(taxes(45000), { tps: 2250, tvq: 4489, total: 51739 });
  assert.deepEqual(taxes(-10000), { tps: -500, tvq: -998, total: -11498 });
  assert.equal(taxes(10000, { exemptTps: true }).tps, 0);
  assert.equal(taxes(427500).tvq, 42643);
});

test('demi-cent arrondi en s\'éloignant de zéro', () => {
  // 20 $ x 9,975 % = 1,995 $ -> 2,00 $
  assert.equal(arrondiTaxe(2000, 9975), 200);
  assert.equal(arrondiTaxe(-2000, 9975), -200);
});

test('gros montants sans perte de précision', () => {
  assert.equal(arrondiTaxe(9_000_000_000_000, 9975), 897_750_000_000);
});

test('refuse les montants non entiers', () => {
  assert.throws(() => arrondiTaxe(10.5, 5000), TypeError);
});

test('montant de ligne après rabais', () => {
  assert.equal(montantLigne(1, 450000, 500), 427500);
  assert.equal(montantLigne(2, 10000, 0), 20000);
});

test('plafond de rabais : escompte moins 35 points, exception, délégation', () => {
  assert.equal(plafondRabaisBp({ escompteBp: 4000 }), 500);
  assert.equal(plafondRabaisBp({ escompteBp: 3000 }), 0);
  assert.equal(plafondRabaisBp({ escompteBp: 4500, exceptionBp: 800 }), 800);
  assert.equal(plafondRabaisBp({ escompteBp: 4000, delegationBp: 1000 }), 1000);
});

test('format monétaire fr-CA', () => {
  assert.match(formatCents(491518).replace(/\s/g, ' '), /^4 915,18 \$$/);
});
