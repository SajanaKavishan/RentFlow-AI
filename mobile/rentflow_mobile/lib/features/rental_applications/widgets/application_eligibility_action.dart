import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shared_widgets.dart';
import '../models/application_eligibility.dart';
import '../services/application_destination.dart';
import '../services/rental_application_api_service.dart';

/// A server-backed action reused by property and Completed viewing details.
class ApplicationEligibilityAction extends StatefulWidget {
  const ApplicationEligibilityAction({
    super.key,
    required this.propertyId,
    required this.apiService,
    this.propertyTitle,
    this.completedViewing = false,
    this.allowNew = true,
  });
  final String propertyId;
  final String? propertyTitle;
  final RentalApplicationApiService apiService;
  final bool completedViewing;
  final bool allowNew;
  @override
  State<ApplicationEligibilityAction> createState() =>
      _ApplicationEligibilityActionState();
}

class _ApplicationEligibilityActionState
    extends State<ApplicationEligibilityAction>
    with WidgetsBindingObserver {
  ApplicationEligibility? _eligibility;
  bool _loading = true;
  bool _opening = false;
  String? _error;
  int _version = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final version = ++_version;
    setState(() {
      _loading = true;
      _eligibility = null;
      _error = null;
    });
    try {
      final result = await widget.apiService.getEligibility(widget.propertyId);
      if (mounted && version == _version) setState(() => _eligibility = result);
    } catch (_) {
      if (mounted && version == _version) {
        setState(
          () => _error =
              'Unable to check application eligibility. Please try again.',
        );
      }
    } finally {
      if (mounted && version == _version) setState(() => _loading = false);
    }
  }

  Future<void> _open() async {
    if (_opening || _loading) return;
    setState(() => _opening = true);
    try {
      final destination = await applicationDestination(
        propertyId: widget.propertyId,
        propertyTitle: widget.propertyTitle,
        apiService: widget.apiService,
        allowNew: widget.allowNew,
      );
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute(builder: (_) => destination));
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) {
        AppSnackbars.show(
          context,
          message: error is RentalApplicationApiException
              ? error.message
              : 'Could not open the application. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final eligibility = _eligibility;
    final available =
        eligibility != null &&
        ((eligibility.canApply && widget.allowNew) ||
            eligibility.hasExistingApplication);
    if (widget.completedViewing && !_loading && _error == null && !available) {
      return const SizedBox.shrink();
    }
    final button = FilledButton(
      key: const Key('details-apply-now'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 52),
        backgroundColor: AppPalette.olive,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
      onPressed: available && !_loading && !_opening ? _open : null,
      child: Text(
        _loading
            ? 'Checking eligibility...'
            : _opening
            ? 'Opening...'
            : eligibility?.hasExistingApplication == true
            ? eligibility!.actionLabel
            : widget.completedViewing && available
            ? 'Apply for this property'
            : available
            ? 'Apply Now'
            : 'Apply after viewing',
        textAlign: TextAlign.center,
      ),
    );
    if (!widget.completedViewing && (available || _loading)) return button;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.completedViewing && available) ...[
          Text(
            eligibility.hasExistingApplication
                ? 'Your application'
                : 'Ready to apply?',
            style: AppTypography.cardTitle.copyWith(
              color: AppPalette.darkOlive,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            eligibility.hasExistingApplication
                ? 'Review or continue your application for this property.'
                : 'If you liked this property, you can start your rental application now.',
          ),
          const SizedBox(height: 12),
        ],
        button,
        if (!available && !_loading) ...[
          const SizedBox(height: 8),
          Text(
            _error ??
                (!widget.allowNew
                    ? 'This property is currently unavailable.'
                    : null) ??
                eligibility?.reason ??
                'Complete a viewing before applying for this property.',
            style: AppTypography.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
        if (_error != null)
          TextButton(
            onPressed: _loading ? null : _refresh,
            child: const Text('Retry eligibility check'),
          ),
      ],
    );
    return widget.completedViewing ? AppCard(child: content) : content;
  }
}
