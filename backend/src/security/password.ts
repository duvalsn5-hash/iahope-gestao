import { HttpError } from '../middleware/errors';

const COMMON = new Set([
  '12345678', '123456789', '1234567890', '87654321', 'password', 'password1', 'senha123', 'senha1234', 'qwerty123',
  'admin123', 'admin1234', 'mudar123', 'trocar123', 'abc12345', 'iahope123', '11111111', '00000000', 'brasil123',
]);

/** Política de senha: 8+ caracteres, letras e números, diferente do usuário e das senhas óbvias. */
export function assertStrongPassword(pw: string, username?: string) {
  const fail = (m: string) => {
    throw new HttpError(422, 'SENHA_FRACA', m);
  };
  if (pw.length < 8) fail('A senha precisa ter pelo menos 8 caracteres');
  if (pw.length > 128) fail('Senha longa demais');
  if (!/[A-Za-zÀ-ÿ]/.test(pw) || !/\d/.test(pw)) fail('Use letras e números na senha');
  if (/^(.)\1+$/.test(pw)) fail('Senha muito fácil (caracteres repetidos)');
  if (COMMON.has(pw.toLowerCase())) fail('Senha muito comum — escolha outra');
  if (username && pw.toLowerCase().includes(username.toLowerCase())) fail('A senha não pode conter o nome de usuário');
}
