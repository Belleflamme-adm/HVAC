import { exigerSession, logout } from './bf-session.js?v=0.2.0';
import { rendreTuiles } from './bf-tuiles.js?v=0.2.0';
import { rendreBandeau } from './bf-bandeau.js?v=0.2.0';

const user = await exigerSession();
if (user) {
  rendreBandeau(document.getElementById('bandeau'), user);
  rendreTuiles(document.getElementById('tuiles'));
  document.getElementById('deconnexion').addEventListener('click', async () => {
    await logout();
    location.replace('/login');
  });
}

if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => {});
