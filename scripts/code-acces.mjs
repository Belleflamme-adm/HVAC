// Produit l'empreinte d'un code d'accès à coller dans la variable Netlify (ex. CODE_ACCES_VENDEURS). ADR-078.
// Usage : node scripts/code-acces.mjs   (le code est demandé au clavier, il n'apparaît pas dans l'historique du terminal)
import { createInterface } from 'node:readline/promises';
import { stdin, stdout } from 'node:process';
import { empreinteCode } from '../public/js/bf-code.js';

const rl = createInterface({ input: stdin, output: stdout });
const code = (await rl.question('Code (4 à 12 chiffres) : ')).trim();
rl.close();
if (!/^\d{4,12}$/.test(code)) { console.error('Le code doit avoir de 4 à 12 chiffres.'); process.exit(1); }
console.log(`\nEmpreinte à coller dans Netlify :\n${await empreinteCode(code)}`);
