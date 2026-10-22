export class DataError extends Error {
  constructor(code, message, status = 500) {
    super(message);
    this.name = 'DataError';
    this.code = code;
    this.status = status;
  }
}

export const desactive = (nom, drapeau) =>
  new DataError('adapter_desactive', `Adapter ${nom} désactivé (${drapeau}=false)`, 503);
