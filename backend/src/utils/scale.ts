/**
 * Etiqueta de balança (padrão brasileiro Toledo/Filizola/Urano, EAN-13):
 *
 *   posição:  0 | 1 … codeLength | … | (12-valueLength) … 11 | 12
 *             prefixo  código        (zeros)   valor              DV
 *
 * Ex.: prefixo 2, código 4 dígitos, valor 5 dígitos em PREÇO:
 *   2 0123 0 01590 D  → produto 123, total R$ 15,90
 */
export interface ScaleConfig {
  prefix: string;
  codeLength: number;
  valueLength: number;
  valueType: 'PRECO' | 'PESO';
}

export interface ScaleRead {
  scaleCode: number;
  /** PRECO: total em reais · PESO: quilos */
  value: number;
  valueType: 'PRECO' | 'PESO';
}

export function ean13CheckOk(code: string): boolean {
  if (!/^\d{13}$/.test(code)) return false;
  const sum = code
    .slice(0, 12)
    .split('')
    .reduce((a, d, i) => a + Number(d) * (i % 2 === 0 ? 1 : 3), 0);
  return (10 - (sum % 10)) % 10 === Number(code[12]);
}

/** Devolve a leitura da etiqueta, ou null se o código não for de balança. */
export function parseScaleBarcode(code: string, cfg: ScaleConfig): ScaleRead | null {
  if (!/^\d{13}$/.test(code) || !code.startsWith(cfg.prefix) || !ean13CheckOk(code)) return null;
  const scaleCode = Number(code.slice(1, 1 + cfg.codeLength));
  const raw = Number(code.slice(12 - cfg.valueLength, 12));
  if (!scaleCode || !raw) return null;
  return {
    scaleCode,
    value: cfg.valueType === 'PRECO' ? raw / 100 : raw / 1000,
    valueType: cfg.valueType,
  };
}
