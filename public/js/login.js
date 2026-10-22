import { login, me } from './bf-session.js?v=0.2.0';

const retour = new URLSearchParams(location.search).get('retour');
const destination = retour && retour.startsWith('/') && !retour.startsWith('//') ? retour : '/';

if (await me()) location.replace(destination);

const form = document.getElementById('form-login');
const msg = document.getElementById('message');
form.addEventListener('submit', async (ev) => {
  ev.preventDefault();
  msg.textContent = '';
  const bouton = form.querySelector('button');
  bouton.disabled = true;
  try {
    await login(form.email.value, form.password.value);
    location.replace(destination);
  } catch (e) {
    msg.textContent = e.message;
  } finally {
    bouton.disabled = false;
  }
});
