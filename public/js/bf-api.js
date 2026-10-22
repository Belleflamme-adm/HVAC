// Appels aux fonctions métier. Le cookie HttpOnly porte la session.
import { appel } from './bf-session.js?v=0.3.0';

const qs = (o = {}) => {
  const p = new URLSearchParams(Object.entries(o).filter(([, v]) => v !== undefined && v !== null && v !== ''));
  return p.toString() ? `?${p}` : '';
};

export const api = {
  get: (fn, query) => appel(fn, { query: qs(query) }),
  post: (fn, body, query) => appel(fn, { method: 'POST', body, query: qs(query) }),
  patch: (fn, body, query) => appel(fn, { method: 'PATCH', body, query: qs(query) }),
  put: (fn, body, query) => appel(fn, { method: 'PUT', body, query: qs(query) }),
  del: (fn, query) => appel(fn, { method: 'DELETE', query: qs(query) }),
};
