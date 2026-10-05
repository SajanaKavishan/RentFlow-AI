class MaintenanceTechnicianChoice {
  const MaintenanceTechnicianChoice({required this.id, required this.name});

  final String id;
  final String name;

  factory MaintenanceTechnicianChoice.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.trim().isEmpty || name is! String) {
      throw const FormatException('Invalid maintenance technician choice.');
    }
    return MaintenanceTechnicianChoice(id: id, name: name);
  }
}
