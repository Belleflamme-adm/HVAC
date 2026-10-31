// Connexion : par code reçu par courriel (sous-traitants, ADR-095) ou par mot de passe (employés).
import { login, me, demanderCode, connecterCode } from './bf-session.js?v=0.4.0';

const retour = new URLSearchParams(location.search).get('retour');
const destination = retour && retour.startsWith('/') && !retour.startsWith('//') ? retour : '/';

if (await me()) location.replace(destination);

const form = document.getElementById('form-login');
const msg = document.getElementById('message');
const info = document.getElementById('info');
const bouton = document.getElementById('bouton');
const zoneCode = document.getElementById('zone-code');
const zoneMdp = document.getElementById('zone-mdp');
const bascule = document.getElementById('bascule');
let mode = 'code';            // 'code' | 'mdp'
let codeDemande = false;

function afficher() {
  zoneMdp.hidden = mode !== 'mdp';
  form.password.required = mode === 'mdp';
  zoneCode.hidden = mode !== 'code' || !codeDemande;
  form.code.required = mode === 'code' && codeDemande;
  bouton.textContent = mode === 'mdp' ? 'Se connecter' : codeDemande ? 'Se connecter' : 'Recevoir un code par courriel';
  bascule.textContent = mode === 'mdp' ? 'Recevoir plutôt un code par courriel' : 'Se connecter avec un mot de passe';
}
bascule.addEventListener('click', () => { mode = mode === 'mdp' ? 'code' : 'mdp'; msg.textContent = ''; info.textContent = ''; afficher(); });
form.email.addEventListener('input', () => { if (codeDemande) { codeDemande = false; info.textContent = ''; afficher(); } });

form.addEventListener('submit', async (ev) => {
  ev.preventDefault();
  msg.textContent = '';
  bouton.disabled = true;
  try {
    if (mode === 'mdp') {
      await login(form.email.value, form.password.value);
      location.replace(destination);
    } else if (!codeDemande) {
      await demanderCode(form.email.value);
      codeDemande = true;
      info.textContent = 'Si ce courriel a un accès, un code à 6 chiffres vient d\'y être envoyé. Il expire rapidement : entre-le tout de suite.';
      afficher();
      form.code.focus();
    } else {
      await connecterCode(form.email.value, form.code.value);
      location.replace(destination);
    }
  } catch (e) {
    msg.textContent = e.message;
  } finally {
    bouton.disabled = false;
  }
});
afficher();
