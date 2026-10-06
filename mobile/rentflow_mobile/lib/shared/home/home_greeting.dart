/// Both mobile homes follow the existing Sri Lanka greeting convention.
String homeGreeting(DateTime instant) {
  final hour = instant.toUtc().add(const Duration(hours: 5, minutes: 30)).hour;
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 17) return 'Good afternoon';
  if (hour >= 17 && hour < 21) return 'Good evening';
  return 'Good night';
}

String homeFirstName(String fullName) {
  final name = fullName.trim();
  return name.isEmpty ? 'there' : name.split(RegExp(r'\s+')).first;
}
