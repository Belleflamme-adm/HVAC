// Conventions de Mike vérifiées sur les fichiers statiques.
import { test } from 'node:test';
import { execFileSync } from 'node:child_process';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

function fichiers(dir, ext) {
  return readdirSync(dir).flatMap((n) => {
    const p = join(dir, n);
    return statSync(p).isDirectory() ? fichiers(p, ext) : (ext.some((e) => p.endsWith(e)) ? [p] : []);
  });
}

const HTML = fichiers('public', ['.html']);
// Librairies tierces figées (public/js/vendor/, version dans le nom) : hors des règles de style de notre code
const JS = fichiers('public', ['.js']).filter((f) => !f.includes('/vendor/'));
const VENDOR = fichiers('public', ['.js']).filter((f) => f.includes('/vendor/'));

test('pretty URLs : aucun lien interne en .html', () => {
  for (const f of [...HTML, ...JS]) {
    const src = readFileSync(f, 'utf8');
    assert.doesNotMatch(src, /href=["'][^"']*\.html/, f);
    assert.doesNotMatch(src, /location\.(?:replace|href)\s*\(?\s*[`'"][^`'"]*\.html/, f);
  }
});

test('scripts et feuilles de style versionnés avec ?v=', () => {
  for (const f of HTML) {
    const src = readFileSync(f, 'utf8');
    for (const m of src.matchAll(/(?:src|href)="(\/(?:js|css)\/[^"]+)"/g)) assert.match(m[1], /\?v=/, `${f} : ${m[1]}`);
  }
});

test('localStorage : seulement des clés bf_*, jamais de jeton ni sessionStorage', () => {
  for (const f of JS) {
    const src = readFileSync(f, 'utf8');
    assert.doesNotMatch(src, /sessionStorage\.setItem/, f);
    for (const m of src.matchAll(/localStorage\.(?:setItem|getItem)\(\s*['"`]([^'"`]+)/g)) assert.match(m[1], /^bf_/, f);
    assert.doesNotMatch(src, /localStorage\.setItem\([^)]*(token|jwt|session|password)/i, f);
  }
});

test('aucune clé service_role ni secret dans le front', () => {
  for (const f of [...HTML, ...JS]) {
    const src = readFileSync(f, 'utf8');
    assert.doesNotMatch(src, /service_role|SERVICE_ROLE|eyJhbGci/, f);
  }
});

test('librairies tierces : version exacte dans le nom du fichier, aucun secret', () => {
  for (const f of VENDOR) {
    assert.match(f, /-\d+\.\d+\.\d+[.-]/, f);
    assert.doesNotMatch(readFileSync(f, 'utf8'), /service_role|SERVICE_ROLE|eyJhbGci/, f);
  }
});

test('aucun tiret cadratin dans les textes', () => {
  for (const f of [...HTML, ...JS, ...fichiers('docs', ['.md']), ...fichiers('netlify', ['.mjs']), ...fichiers('lib', ['.js'])]) {
    assert.doesNotMatch(readFileSync(f, 'utf8'), /\u2014/, f);
  }
});

// Une erreur de syntaxe dans une page ne serait vue qu'au chargement dans le navigateur : on la bloque ici
test('syntaxe valide pour tous les scripts du front', () => {
  for (const f of JS) execFileSync(process.execPath, ['--check', f], { stdio: 'pipe' });
});
