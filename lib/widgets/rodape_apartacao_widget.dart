import 'package:flutter/material.dart';

class RodapeApartacaoWidget extends StatelessWidget {
  final VoidCallback onFiltroApartacaoTap;
  final VoidCallback onConsultarMaeTap;

  const RodapeApartacaoWidget({
    super.key,
    required this.onFiltroApartacaoTap,
    required this.onConsultarMaeTap,
  });

  @override
  Widget build(BuildContext context) {
    const Color corDestaqueRodape = Color(0xFF18385F);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            onTap: onFiltroApartacaoTap,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.filter_alt_outlined,
                    color: corDestaqueRodape,
                    size: 18,
                  ),
                  SizedBox(width: 4),
                  Text(
                    "Filtro Apartação",
                    style: TextStyle(
                      color: corDestaqueRodape,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          InkWell(
            onTap: onConsultarMaeTap,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search_outlined,
                    color: Color(0xFF18385F),
                    size: 18,
                  ),
                  SizedBox(width: 4),
                  Text(
                    "Consultar Mãe",
                    style: TextStyle(
                      color: Color(0xFF18385F),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
