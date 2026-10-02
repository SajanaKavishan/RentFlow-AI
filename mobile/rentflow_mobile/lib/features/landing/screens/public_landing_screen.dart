import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/rentflow_brand.dart';
import '../../auth/screens/login_screen.dart';
import '../../auth/screens/register_screen.dart';
import '../services/feedback_service.dart';

class PublicLandingScreen extends StatefulWidget {
  const PublicLandingScreen({
    super.key,
    this.feedbackService = const UnavailableFeedbackService(),
  });

  final FeedbackService feedbackService;

  @override
  State<PublicLandingScreen> createState() => _PublicLandingScreenState();
}

class _PublicLandingScreenState extends State<PublicLandingScreen>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  final _platformKey = GlobalKey();
  late final AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _open(Widget screen) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, animation, secondaryAnimation) => screen,
        transitionsBuilder: (_, animation, secondaryAnimation, child) =>
            FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, .025),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
        transitionDuration: const Duration(milliseconds: 360),
      ),
    );
  }

  Future<void> _explore() async {
    final heroExtent = math.max(MediaQuery.sizeOf(context).height, 680);
    await _scrollController.animateTo(
      heroExtent
          .clamp(0, _scrollController.position.maxScrollExtent)
          .toDouble(),
      duration: const Duration(milliseconds: 720),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: _LandingColors.olive900,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        key: const Key('public-landing'),
        backgroundColor: AppPalette.authCard,
        body: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(child: _hero(context)),
            SliverToBoxAdapter(
              child: _RevealOnScroll(
                controller: _scrollController,
                child: KeyedSubtree(key: _platformKey, child: _platform()),
              ),
            ),
            SliverToBoxAdapter(
              child: _RevealOnScroll(
                controller: _scrollController,
                child: _journey(),
              ),
            ),
            SliverToBoxAdapter(
              child: _RevealOnScroll(
                controller: _scrollController,
                child: _smartAssistance(),
              ),
            ),
            SliverToBoxAdapter(
              child: _RevealOnScroll(
                controller: _scrollController,
                child: _connectedExperience(),
              ),
            ),
            SliverToBoxAdapter(
              child: _RevealOnScroll(
                controller: _scrollController,
                child: _highlights(),
              ),
            ),
            SliverToBoxAdapter(
              child: _RevealOnScroll(
                controller: _scrollController,
                child: _FeedbackSection(service: widget.feedbackService),
              ),
            ),
            const SliverToBoxAdapter(child: _LandingFooter()),
          ],
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final animation = reduceMotion
        ? const AlwaysStoppedAnimation<double>(1)
        : CurvedAnimation(
            parent: _entranceController,
            curve: Curves.easeOutCubic,
          );

    return SizedBox(
      key: const Key('public-hero'),
      height: math.max(viewportHeight, 680),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ScaleTransition(
            scale: Tween(begin: 1.045, end: 1.0).animate(animation),
            child: Image.asset(
              'assets/auth/residence.png',
              fit: BoxFit.cover,
              alignment: const Alignment(.25, 0),
              excludeFromSemantics: true,
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xEE1A2210), Color(0xA63A4726)],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FadeTransition(
                    opacity: animation,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Semantics(
                                label: 'RentFlow AI',
                                child: const RentFlowBrand(
                                  markSize: 44,
                                  textSize: 17,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        OutlinedButton(
                          key: const Key('public-sign-in'),
                          onPressed: () => _open(const LoginScreen()),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0x66FFFFFF)),
                            minimumSize: const Size(76, 40),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            shape: const StadiumBorder(),
                          ),
                          child: const Text(
                            'Sign In',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _HeroEntrance(
                              animation: _entranceController,
                              interval: const Interval(.12, .68),
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'A BETTER WAY TO RENT',
                                    style: TextStyle(
                                      color: _LandingColors.sage,
                                      fontSize: AppTypography.captionSize,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.8,
                                    ),
                                  ),
                                  SizedBox(height: 20),
                                  Text(
                                    'Find your perfect home, smarter.',
                                    key: Key('public-hero-title'),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: AppTypography.displaySize,
                                      height: 1.15,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                  SizedBox(height: 22),
                                  Text(
                                    'AI-powered rental search and management for a simpler rental journey.',
                                    style: TextStyle(
                                      color: Color(0xD9FFFFFF),
                                      fontSize: AppTypography.cardTitleSize,
                                      height: 1.55,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 34),
                            _HeroEntrance(
                              animation: _entranceController,
                              interval: const Interval(.35, 1),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 310,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      FilledButton.icon(
                                        key: const Key('public-get-started'),
                                        onPressed: () =>
                                            _open(const RegisterScreen()),
                                        iconAlignment: IconAlignment.end,
                                        icon: const Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 19,
                                        ),
                                        label: const Text('Get Started'),
                                        style: FilledButton.styleFrom(
                                          minimumSize: const Size.fromHeight(
                                            52,
                                          ),
                                          foregroundColor:
                                              _LandingColors.olive900,
                                          backgroundColor: _LandingColors.sage,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          textStyle: AppTypography.button,
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      OutlinedButton.icon(
                                        key: const Key('public-explore'),
                                        onPressed: _explore,
                                        iconAlignment: IconAlignment.end,
                                        label: const Text(
                                          'Explore the platform',
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          minimumSize: const Size.fromHeight(
                                            48,
                                          ),
                                          foregroundColor: Colors.white,
                                          side: const BorderSide(
                                            color: Color(0x73FFFFFF),
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          textStyle: AppTypography.button,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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

  Widget _platform() => _LandingSection(
    key: const Key('public-platform'),
    eyebrow: 'THE PLATFORM',
    title: 'Everything you need for the rental journey.',
    child: Column(
      children: const [
        _FeatureCard(
          icon: Icons.search_rounded,
          title: 'Property Discovery',
          copy: 'Find places that fit what you are looking for.',
        ),
        _FeatureCard(
          icon: Icons.calendar_month_outlined,
          title: 'Viewings & Applications',
          copy: 'Request viewings and manage supporting documents.',
        ),
        _FeatureCard(
          icon: Icons.description_outlined,
          title: 'Lease & Payments',
          copy: 'Keep agreements and payment activity organized.',
        ),
        _FeatureCard(
          icon: Icons.handyman_outlined,
          title: 'Maintenance & Support',
          copy: 'Handle requests and ongoing rental support.',
        ),
      ],
    ),
  );

  Widget _journey() => const _LandingSection(
    surface: Colors.white,
    centered: true,
    eyebrow: 'HOW IT WORKS',
    title: 'One connected rental journey.',
    subtitle:
        'From the first search to ongoing support, each step stays clear.',
    child: Column(
      children: [
        _JourneyStep('01', 'Discover', 'Find places that fit your needs.'),
        _JourneyStep('02', 'View', 'Request and manage property viewings.'),
        _JourneyStep('03', 'Apply', 'Submit your application and documents.'),
        _JourneyStep('04', 'Rent', 'Move into the lease and payment journey.'),
        _JourneyStep('05', 'Get Support', 'Handle ongoing rental needs.'),
      ],
    ),
  );

  Widget _smartAssistance() => const _LandingSection(
    surface: _LandingColors.olive900,
    dark: true,
    eyebrow: 'SMART ASSISTANCE',
    title: 'Smarter help throughout your rental journey.',
    subtitle:
        'AI-assisted features make searching, applying, pricing and maintenance easier to manage.',
    child: Column(
      children: [
        _DarkFeatureCard(
          Icons.auto_awesome_outlined,
          'Find better matches',
          'Surface properties that better fit renter needs.',
        ),
        _DarkFeatureCard(
          Icons.fact_check_outlined,
          'Apply with fewer surprises',
          'Spot missing information before review.',
        ),
        _DarkFeatureCard(
          Icons.insights_outlined,
          'Make informed decisions',
          'Use clearer pricing and rental insights.',
        ),
        _DarkFeatureCard(
          Icons.build_circle_outlined,
          'Resolve maintenance faster',
          'Understand and coordinate requests efficiently.',
        ),
        _TrustCard(),
      ],
    ),
  );

  Widget _connectedExperience() => const _LandingSection(
    eyebrow: 'ONE CONNECTED EXPERIENCE',
    title: 'Your rental journey, kept together.',
    child: Column(
      children: [
        _ConnectedCard(
          Icons.home_work_outlined,
          'Everything in one place',
          'Viewings, applications, leases, payments and support stay connected.',
        ),
        _ConnectedCard(
          Icons.devices_outlined,
          'Web and mobile',
          'Continue rental tasks across RentFlow experiences.',
          tint: _LandingColors.sage,
        ),
        _ConnectedCard(
          Icons.trending_up_rounded,
          'Clear progress',
          'Understand where things stand and what happens next.',
          tint: _LandingColors.olive700,
          dark: true,
        ),
      ],
    ),
  );

  Widget _highlights() => _LandingSection(
    key: const Key('renting-simplified'),
    centered: true,
    eyebrow: 'RENTING, SIMPLIFIED',
    title: 'Built around a simpler rental experience.',
    subtitle: 'Clearer steps, connected tools and smarter assistance.',
    child: _ProductHighlightsRail(pageController: _scrollController),
  );
}

class _HeroEntrance extends StatelessWidget {
  const _HeroEntrance({
    required this.animation,
    required this.interval,
    required this.child,
  });

  final AnimationController animation;
  final Interval interval;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return child;
    final curved = CurvedAnimation(parent: animation, curve: interval);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, .08),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

class _RevealOnScroll extends StatefulWidget {
  const _RevealOnScroll({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  State<_RevealOnScroll> createState() => _RevealOnScrollState();
}

class _RevealOnScrollState extends State<_RevealOnScroll> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_checkVisibility);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_checkVisibility);
    super.dispose();
  }

  void _checkVisibility() {
    if (_visible || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    if (top < viewportHeight * .9) setState(() => _visible = true);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final visible = reduceMotion || _visible;
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, .035),
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _LandingSection extends StatelessWidget {
  const _LandingSection({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.child,
    this.subtitle,
    this.surface = AppPalette.authCard,
    this.dark = false,
    this.centered = false,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget child;
  final Color surface;
  final bool dark;
  final bool centered;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: surface,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 72, 20, 68),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: centered
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow,
                textAlign: centered ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                  color: dark ? _LandingColors.sage : _LandingColors.olive700,
                  fontSize: AppTypography.captionSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: centered ? TextAlign.center : TextAlign.start,
                style: AppTypography.pageTitle.copyWith(
                  color: dark ? Colors.white : _LandingColors.ink,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 16),
                Text(
                  subtitle!,
                  textAlign: centered ? TextAlign.center : TextAlign.start,
                  style: TextStyle(
                    color: dark
                        ? const Color(0xB8FFFFFF)
                        : _LandingColors.muted,
                    fontSize: AppTypography.bodySize,
                    height: 1.55,
                  ),
                ),
              ],
              const SizedBox(height: 34),
              child,
            ],
          ),
        ),
      ),
    ),
  );
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.copy,
  });
  final IconData icon;
  final String title;
  final String copy;

  @override
  Widget build(BuildContext context) => _LandingCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IconTile(icon),
        const SizedBox(width: 16),
        Expanded(child: _CardCopy(title, copy)),
      ],
    ),
  );
}

class _JourneyStep extends StatelessWidget {
  const _JourneyStep(this.number, this.title, this.copy);
  final String number;
  final String title;
  final String copy;

  @override
  Widget build(BuildContext context) => _LandingCard(
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppPalette.authCard,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFCBD4B7)),
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: _LandingColors.olive900,
              fontSize: AppTypography.captionSize,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: _CardCopy(title, copy)),
      ],
    ),
  );
}

class _DarkFeatureCard extends StatelessWidget {
  const _DarkFeatureCard(this.icon, this.title, this.copy);
  final IconData icon;
  final String title;
  final String copy;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0x0FFFFFFF),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0x24FFFFFF)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IconTile(icon),
        const SizedBox(width: 16),
        Expanded(child: _CardCopy(title, copy, dark: true)),
      ],
    ),
  );
}

class _TrustCard extends StatelessWidget {
  const _TrustCard();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _LandingColors.olive700,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0x42DDE5CC)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.verified_user_outlined, color: _LandingColors.sage),
        SizedBox(width: 14),
        Expanded(
          child: _CardCopy(
            'AI helps with the work. People stay in control.',
            'Important rental decisions remain human-controlled.',
            dark: true,
          ),
        ),
      ],
    ),
  );
}

class _ConnectedCard extends StatelessWidget {
  const _ConnectedCard(
    this.icon,
    this.title,
    this.copy, {
    this.tint = Colors.white,
    this.dark = false,
  });
  final IconData icon;
  final String title;
  final String copy;
  final Color tint;
  final bool dark;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: dark ? const Color(0x2EFFFFFF) : AppPalette.authBorder,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IconTile(icon),
        const SizedBox(height: 20),
        _CardCopy(title, copy, dark: dark),
      ],
    ),
  );
}

class _ProductHighlightsRail extends StatefulWidget {
  const _ProductHighlightsRail({required this.pageController});

  final ScrollController pageController;

  @override
  State<_ProductHighlightsRail> createState() => _ProductHighlightsRailState();
}

class _ProductHighlightsRailState extends State<_ProductHighlightsRail>
    with SingleTickerProviderStateMixin {
  static const _cardWidth = 220.0;
  static const _cardGap = 10.0;
  static const _highlights = [
    'Easy property discovery',
    'Clear viewing requests',
    'Simple rental applications',
    'Secure document handling',
    'Smarter property matching',
    'Clear application progress',
    'Helpful pricing insights',
    'Human-controlled decisions',
    'Connected web and mobile experience',
    'Organized lease and payment workflows',
    'Faster maintenance coordination',
    'Clear status updates',
  ];

  final _railController = ScrollController();
  late final AnimationController _motionController;
  bool _reduceMotion = false;
  bool _userInteracted = false;

  double get _cycleExtent => _highlights.length * (_cardWidth + _cardGap);

  @override
  void initState() {
    super.initState();
    _motionController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 42),
    )..addListener(_advanceRail);
    widget.pageController.addListener(_updateMotion);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateMotion());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (_reduceMotion) {
      _motionController.stop();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateMotion());
    }
  }

  @override
  void didUpdateWidget(covariant _ProductHighlightsRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageController == widget.pageController) return;
    oldWidget.pageController.removeListener(_updateMotion);
    widget.pageController.addListener(_updateMotion);
  }

  @override
  void dispose() {
    widget.pageController.removeListener(_updateMotion);
    _motionController.dispose();
    _railController.dispose();
    super.dispose();
  }

  void _advanceRail() {
    if (!_railController.hasClients || _userInteracted || _reduceMotion) return;
    final target = _cycleExtent * (1 - _motionController.value);
    _railController.jumpTo(
      target.clamp(0, _railController.position.maxScrollExtent).toDouble(),
    );
  }

  void _updateMotion() {
    if (!mounted || _userInteracted || _reduceMotion) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final top = renderObject.localToGlobal(Offset.zero).dy;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final visible =
        top < viewportHeight * 1.2 &&
        top + renderObject.size.height > -viewportHeight * .2;
    if (visible && !_motionController.isAnimating) {
      if (_railController.hasClients) {
        _motionController.value = 0;
        _railController.jumpTo(
          _cycleExtent
              .clamp(0, _railController.position.maxScrollExtent)
              .toDouble(),
        );
        _motionController.repeat();
      }
    } else if (!visible && _motionController.isAnimating) {
      _motionController.stop();
    }
  }

  void _pauseForInteraction(PointerDownEvent event) {
    _userInteracted = true;
    _motionController.stop();
  }

  Widget _sequence({required bool duplicate}) => ExcludeSemantics(
    excluding: duplicate,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final highlight in _highlights)
          Padding(
            padding: const EdgeInsets.only(right: _cardGap),
            child: _HighlightCard(label: highlight),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Product experience highlights',
    child: Listener(
      onPointerDown: _pauseForInteraction,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        key: const Key('product-highlights-rail'),
        height: 76,
        child: SingleChildScrollView(
          controller: _railController,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          child: Row(
            children: [_sequence(duplicate: false), _sequence(duplicate: true)],
          ),
        ),
      ),
    ),
  );
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    width: _ProductHighlightsRailState._cardWidth,
    height: 76,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFCF4),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFDAD7C7)),
    ),
    child: Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: _LandingColors.sage,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 17,
            color: _LandingColors.olive700,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _LandingColors.olive900,
              fontSize: AppTypography.bodySmallSize,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _LandingCard extends StatelessWidget {
  const _LandingCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .82),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppPalette.authBorder),
    ),
    child: child,
  );
}

class _IconTile extends StatelessWidget {
  const _IconTile(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: _LandingColors.sage,
      borderRadius: BorderRadius.circular(13),
    ),
    child: Icon(icon, size: 22, color: _LandingColors.olive900),
  );
}

class _CardCopy extends StatelessWidget {
  const _CardCopy(this.title, this.copy, {this.dark = false});
  final String title;
  final String copy;
  final bool dark;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          color: dark ? Colors.white : _LandingColors.ink,
          fontSize: AppTypography.bodyLargeSize,
          height: 1.25,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 7),
      Text(
        copy,
        style: TextStyle(
          color: dark ? const Color(0xB8FFFFFF) : _LandingColors.muted,
          fontSize: AppTypography.bodySmallSize,
          height: 1.5,
        ),
      ),
    ],
  );
}

class _FeedbackSection extends StatefulWidget {
  const _FeedbackSection({required this.service});

  final FeedbackService service;

  @override
  State<_FeedbackSection> createState() => _FeedbackSectionState();
}

class _FeedbackSectionState extends State<_FeedbackSection> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _messageController = TextEditingController();
  bool _submitting = false;
  bool _sent = false;
  String? _status;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, String hint) => InputDecoration(
    labelText: label,
    hintText: hint,
    alignLabelWithHint: true,
    filled: true,
    fillColor: const Color(0xFFFFFEFA),
    counterText: '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    labelStyle: const TextStyle(color: _LandingColors.olive700),
    hintStyle: TextStyle(color: _LandingColors.muted.withValues(alpha: .72)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppPalette.authBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: _LandingColors.olive700, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF9A463E)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF9A463E), width: 1.4),
    ),
  );

  String? _required(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label is required.';
    return null;
  }

  String? _emailValidator(String? value) {
    final requiredError = _required(value, 'Email');
    if (requiredError != null) return requiredError;
    final email = value!.trim();
    final valid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
    return valid ? null : 'Enter a valid email address.';
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _status = null;
      _sent = false;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);
    try {
      await widget.service.send(
        FeedbackMessage(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          message: _messageController.text.trim(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _sent = true;
        _status = 'Message sent.';
      });
    } on FeedbackTransportUnavailable {
      if (!mounted) return;
      setState(() {
        _status =
            'Message delivery is not connected yet. Your details have not been sent.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = 'Message delivery is unavailable. Please try again later.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => _LandingSection(
    key: const Key('feedback-section'),
    eyebrow: "LET'S TALK",
    title: 'Have a question\nor feedback?',
    subtitle: "We'd love to hear about your RentFlow experience.",
    surface: const Color(0xFFF5F1E7),
    child: Form(
      key: _formKey,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .84),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppPalette.authBorder),
        ),
        child: Column(
          children: [
            TextFormField(
              key: const Key('feedback-name'),
              controller: _nameController,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              maxLength: 80,
              inputFormatters: [LengthLimitingTextInputFormatter(80)],
              decoration: _decoration('Name', 'Your name'),
              validator: (value) => _required(value, 'Name'),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('feedback-email'),
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              maxLength: 160,
              inputFormatters: [LengthLimitingTextInputFormatter(160)],
              decoration: _decoration('Email', 'you@example.com'),
              validator: _emailValidator,
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const Key('feedback-message'),
              controller: _messageController,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              minLines: 4,
              maxLines: 7,
              maxLength: 1500,
              inputFormatters: [LengthLimitingTextInputFormatter(1500)],
              decoration: _decoration('Message', 'How can we help?'),
              validator: (value) => _required(value, 'Message'),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                key: const Key('feedback-submit'),
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: _LandingColors.olive900,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _LandingColors.olive900.withValues(
                    alpha: .6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: AppTypography.bodySize,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(_submitting ? 'Sending…' : 'Send message'),
              ),
            ),
            if (_status != null) ...[
              const SizedBox(height: 14),
              Container(
                key: const Key('feedback-status'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _sent
                      ? _LandingColors.sage.withValues(alpha: .65)
                      : const Color(0xFFFFF7DF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _status!,
                  style: const TextStyle(
                    color: _LandingColors.olive900,
                    fontSize: AppTypography.labelSize,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _LandingFooter extends StatelessWidget {
  const _LandingFooter();

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const Key('public-footer'),
    color: AppPalette.authCard,
    child: const SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Text(
          '© 2026 RentFlow AI. All rights reserved.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _LandingColors.muted,
            fontSize: AppTypography.captionSize,
          ),
        ),
      ),
    ),
  );
}

abstract final class _LandingColors {
  static const olive900 = Color(0xFF1C2619);
  static const olive700 = Color(0xFF5D6842);
  static const sage = Color(0xFFDDE5CC);
  static const ink = Color(0xFF20211D);
  static const muted = Color(0xFF737368);
}
