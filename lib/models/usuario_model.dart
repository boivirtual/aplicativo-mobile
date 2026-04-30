class Usuario {
  final String id;
  final String nome;
  final List<Map<String, String>>
  fazendas; // Aqui guardaremos o ID e Nome das fazendas

  Usuario({required this.id, required this.nome, required this.fazendas});

  // Fábrica para criar o usuário a partir do JSON da sua API
  factory Usuario.fromJson(Map<String, dynamic> json) {
    var listaLocal = json['local'] as List;
    List<Map<String, String>> fazendasFormatadas = listaLocal.map((item) {
      return {"id": item['id'].toString(), "nome": item['nome'].toString()};
    }).toList();

    return Usuario(
      id: json['id'].toString(),
      nome: json['nome'].toString(),
      fazendas: fazendasFormatadas,
    );
  }
}
