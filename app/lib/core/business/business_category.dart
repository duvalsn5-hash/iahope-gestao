import 'package:flutter/material.dart';

/// Ramo de negócio da empresa. O Master escolhe ao criar o cliente; o app usa
/// para sugerir módulos, categorias de produto e adaptar textos e dicas.
class BusinessCategory {
  const BusinessCategory({
    required this.code,
    required this.label,
    required this.icon,
    required this.description,
    required this.modules,
    required this.productCategories,
    this.productsLabel = 'Produtos',
    this.units = const ['UN'],
    this.tips = const [],
    this.comingSoon,
  });

  /// Código gravado no banco (tenants.business_category).
  final String code;
  final String label;
  final IconData icon;
  final String description;

  /// Módulos que já vêm marcados para esse ramo.
  final List<String> modules;

  /// Categorias de produto sugeridas no cadastro.
  final List<String> productCategories;

  /// Nome do menu de produtos para esse ramo.
  final String productsLabel;

  /// Unidades mais usadas (aparecem primeiro).
  final List<String> units;

  /// Primeiros passos sugeridos para o administrador da empresa.
  final List<String> tips;

  /// Recursos específicos ainda em construção para o ramo (aparece como aviso).
  final String? comingSoon;
}

const kBusinessCategories = <BusinessCategory>[
  BusinessCategory(
    code: 'OFICINA_MOTO',
    label: 'Oficina de moto',
    icon: Icons.two_wheeler,
    description: 'Ordens de serviço, motos dos clientes, mão de obra, peças e revisões',
    modules: ['PDV', 'FINANCEIRO', 'COMPRAS', 'OFICINA'],
    productsLabel: 'Peças e produtos',
    productCategories: [
      'Óleos e lubrificantes', 'Pneus e câmaras', 'Freios', 'Relação (kit transmissão)', 'Motor',
      'Elétrica e iluminação', 'Suspensão', 'Filtros', 'Cabos', 'Carenagem', 'Acessórios', 'Capacetes',
    ],
    units: ['UN', 'PC', 'L', 'ML', 'KIT'],
    tips: [
      'Cadastre os mecânicos em Usuários (com a % de comissão).',
      'Em Oficina → Mão de obra, carregue os serviços padrão e ajuste os preços.',
      'Cadastre as peças com foto e código de barras (ou importe o XML da nota do fornecedor).',
      'Abra o caixa no PDV e receba a primeira moto em Oficina → Receber moto.',
    ],
  ),
  BusinessCategory(
    code: 'MERCADINHO',
    label: 'Mercadinho',
    icon: Icons.storefront,
    description: 'PDV rápido com leitor e balança, estoque, fiado e compras por XML',
    modules: ['PDV', 'FINANCEIRO', 'COMPRAS', 'BALANCA'],
    productCategories: [
      'Mercearia', 'Bebidas', 'Frios e laticínios', 'Açougue', 'Hortifruti', 'Padaria',
      'Limpeza', 'Higiene e perfumaria', 'Bomboniere', 'Congelados', 'Pet', 'Utilidades',
    ],
    units: ['UN', 'KG', 'G', 'L', 'CX', 'PCT', 'FD', 'DZ'],
    tips: [
      'Importe o XML das notas de compra: produtos, custo e estoque entram sozinhos.',
      'Configure a balança em Empresa e informe o código da balança nos pesáveis.',
      'Cadastre os clientes do fiado e use “A prazo” no pagamento.',
      'Abra o caixa e venda: bipe o código ou digite 3* antes para lançar 3 unidades.',
    ],
  ),
  BusinessCategory(
    code: 'ESTAMPARIA',
    label: 'Estamparia e personalizados',
    icon: Icons.format_paint_outlined,
    description: 'Camisetas, canecas, brindes: pedidos sob encomenda, arte, sinal e entrega',
    modules: ['PDV', 'FINANCEIRO', 'COMPRAS'],
    productCategories: [
      'Camisetas', 'Camisas polo', 'Moletons', 'Bonés', 'Canecas', 'Squeezes e garrafas', 'Ecobags',
      'Uniformes', 'Brindes', 'Adesivos', 'Insumos (tinta, papel, filme)', 'Serviço de estampa',
    ],
    units: ['UN', 'PC', 'M', 'RL', 'CX'],
    tips: [
      'Cadastre as peças lisas (camiseta P/M/G, caneca…) com o custo para ver a margem.',
      'Cadastre os insumos (tinta, papel, filme DTF) na categoria Insumos.',
      'Cadastre os clientes (empresas, escolas, eventos) para vender a prazo.',
      'Use o PDV para vendas de balcão e o Financeiro para controlar os sinais recebidos.',
    ],
    comingSoon: 'Pedidos sob encomenda com arte, aprovação, sinal, grade de tamanhos e fila de produção.',
  ),
  BusinessCategory(
    code: 'MODA',
    label: 'Loja de roupas e calçados',
    icon: Icons.checkroom_outlined,
    description: 'Roupas, calçados e acessórios: grade de tamanho e cor, trocas e crediário',
    modules: ['PDV', 'FINANCEIRO', 'COMPRAS'],
    productCategories: [
      'Camisetas', 'Blusas', 'Camisas', 'Calças', 'Bermudas e shorts', 'Saias', 'Vestidos',
      'Moda íntima', 'Moda praia', 'Infantil', 'Calçados', 'Bolsas', 'Acessórios',
    ],
    units: ['UN', 'PC', 'PAR', 'CJ'],
    tips: [
      'Cadastre cada tamanho/cor como um produto (ex.: “Camiseta básica preta M”) com código de barras.',
      'Use as categorias (Calças, Vestidos…) para achar rápido no cadastro.',
      'Importe o XML da nota do fornecedor para dar entrada no estoque.',
      'Cadastre os clientes do crediário e use “A prazo” no pagamento.',
    ],
    comingSoon: 'Grade de tamanho e cor automática, etiquetas com código de barras, trocas com vale e condicional.',
  ),
  BusinessCategory(
    code: 'LOJA',
    label: 'Loja / varejo em geral',
    icon: Icons.point_of_sale,
    description: 'Variedades, papelaria, eletrônicos, material de construção…',
    modules: ['PDV', 'FINANCEIRO', 'COMPRAS'],
    productCategories: ['Geral', 'Papelaria', 'Eletrônicos', 'Utilidades', 'Ferramentas', 'Presentes', 'Serviços'],
    units: ['UN', 'PC', 'CX', 'M', 'KG'],
    tips: [
      'Cadastre os produtos (ou importe o XML das notas de compra).',
      'Cadastre os usuários de caixa em Usuários.',
      'Abra o caixa no PDV e faça a primeira venda.',
    ],
  ),
  BusinessCategory(
    code: 'DISTRIBUIDORA',
    label: 'Distribuidora / logística',
    icon: Icons.local_shipping,
    description: 'Descarga hora a hora, docas e cargas, mais venda e compras',
    modules: ['PDV', 'FINANCEIRO', 'COMPRAS', 'PRODUTIVIDADE'],
    productCategories: ['Bebidas', 'Alimentos', 'Limpeza', 'Higiene', 'Embalagens', 'Descartáveis'],
    units: ['UN', 'CX', 'FD', 'PCT', 'KG'],
    tips: [
      'Cadastre os operadores de doca em Usuários (perfil Operador).',
      'Em Produtividade, lance as cargas e acompanhe a descarga hora a hora.',
      'Importe o XML das notas para dar entrada no estoque.',
    ],
  ),
  BusinessCategory(
    code: 'OUTRO',
    label: 'Outro ramo',
    icon: Icons.category_outlined,
    description: 'Escolha os módulos à mão',
    modules: ['PDV', 'FINANCEIRO'],
    productCategories: ['Geral', 'Serviços'],
  ),
];

BusinessCategory businessCategoryOf(String? code) =>
    kBusinessCategories.firstWhere((c) => c.code == code, orElse: () => kBusinessCategories.last);
