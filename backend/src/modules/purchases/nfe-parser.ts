import { XMLParser } from 'fast-xml-parser';
import { HttpError } from '../../middleware/errors';

/** Dados que interessam de uma NF-e (modelo 55) para dar entrada no estoque. */
export interface ParsedNfe {
  accessKey: string | null;
  number: string;
  series: string;
  issueDate: string; // YYYY-MM-DD
  supplier: {
    doc: string;
    name: string;
    tradeName?: string;
    ie?: string;
    phone?: string;
    zip?: string;
    street?: string;
    number?: string;
    district?: string;
    city?: string;
    state?: string;
  };
  recipientDoc: string | null;
  total: number;
  items: {
    line: number;
    supplierCode: string;
    barcode: string | null;
    description: string;
    ncm?: string;
    unit: string;
    qty: number;
    unitPrice: number;
    total: number;
  }[];
  installments: { document: string; dueDate: string; amount: number }[];
}

const asArray = <T>(v: T | T[] | undefined): T[] => (v == null ? [] : Array.isArray(v) ? v : [v]);
const str = (v: unknown) => (v == null ? '' : String(v).trim());
const numv = (v: unknown) => Number(String(v ?? '0').replace(',', '.')) || 0;

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: '@',
  removeNSPrefix: true,
  parseTagValue: false, // mantém zeros à esquerda (códigos, CEP, EAN)
  trimValues: true,
});

export function parseNfeXml(xml: string): ParsedNfe {
  let doc: any;
  try {
    doc = parser.parse(xml);
  } catch {
    throw new HttpError(400, 'XML_INVALIDO', 'Arquivo não é um XML válido');
  }
  const nfe = doc?.nfeProc?.NFe ?? doc?.NFe;
  const inf = nfe?.infNFe;
  if (!inf) throw new HttpError(400, 'XML_INVALIDO', 'O arquivo não é o XML de uma NF-e');

  const ide = inf.ide ?? {};
  if (str(ide.mod) && str(ide.mod) !== '55') {
    throw new HttpError(400, 'XML_INVALIDO', `Modelo ${ide.mod} não suportado (use NF-e modelo 55)`);
  }
  const emit = inf.emit ?? {};
  const end = emit.enderEmit ?? {};
  const keyFromProt = str(doc?.nfeProc?.protNFe?.infProt?.chNFe);
  const keyFromId = str(inf['@Id']).replace(/^NFe/, '');
  const accessKey = /^\d{44}$/.test(keyFromProt) ? keyFromProt : /^\d{44}$/.test(keyFromId) ? keyFromId : null;

  const items = asArray(inf.det).map((d: any, i: number) => {
    const p = d.prod ?? {};
    const ean = str(p.cEAN);
    return {
      line: Number(d['@nItem'] ?? i + 1),
      supplierCode: str(p.cProd),
      barcode: /^\d{8,14}$/.test(ean) ? ean : null, // "SEM GTIN" vira null
      description: str(p.xProd),
      ncm: str(p.NCM) || undefined,
      unit: str(p.uCom).toUpperCase() || 'UN',
      qty: numv(p.qCom),
      unitPrice: numv(p.vUnCom),
      total: numv(p.vProd) - numv(p.vDesc) + numv(p.vFrete) + numv(p.vOutro) + numv(p.vSeg),
    };
  });
  if (!items.length) throw new HttpError(400, 'XML_INVALIDO', 'NF-e sem itens');

  const installments = asArray(inf.cobr?.dup).map((d: any, i: number) => ({
    document: str(d.nDup) || String(i + 1).padStart(3, '0'),
    dueDate: str(d.dVenc).slice(0, 10),
    amount: numv(d.vDup),
  }));

  return {
    accessKey,
    number: str(ide.nNF),
    series: str(ide.serie),
    issueDate: str(ide.dhEmi || ide.dEmi).slice(0, 10),
    supplier: {
      doc: str(emit.CNPJ || emit.CPF),
      name: str(emit.xNome),
      tradeName: str(emit.xFant) || undefined,
      ie: str(emit.IE) || undefined,
      phone: str(end.fone) || undefined,
      zip: str(end.CEP) || undefined,
      street: str(end.xLgr) || undefined,
      number: str(end.nro) || undefined,
      district: str(end.xBairro) || undefined,
      city: str(end.xMun) || undefined,
      state: str(end.UF) || undefined,
    },
    recipientDoc: str(inf.dest?.CNPJ || inf.dest?.CPF) || null,
    total: numv(inf.total?.ICMSTot?.vNF),
    items,
    installments,
  };
}
