String formatLkr(double amount) {
  final parts = amount.toStringAsFixed(2).split('.');
  final grouped = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return 'Rs. $grouped.${parts[1]}';
}
