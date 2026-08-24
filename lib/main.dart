import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'tm_parser.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const TMUtilityApp());
}

// ─── Color Palette ───────────────────────────────────────────────────────────
class AppColors {
  static const Color background = Color(0xFFF4F7FA);
  static const Color cardBg = Colors.white;
  static const Color textDark = Color(0xFF1A1A2E);
  static const Color textMid = Color(0xFF6B7280);
  static const Color textLight = Color(0xFFADB5BD);

  static const Color gradStart = Color(0xFF0A4D68);
  static const Color gradMid = Color(0xFF0077A8);
  static const Color gradEnd = Color(0xFF00C9FF);

  static const Color ringInternet = Color(0xFF00B4D8);
  static const Color ringMinutes = Color(0xFF845EC2);
  static const Color ringSMS = Color(0xFFF4A261);

  static const LinearGradient mainGradient = LinearGradient(
    colors: [gradStart, gradMid, gradEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient btnGradient = LinearGradient(
    colors: [gradMid, gradEnd],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}

// ─── App Root ────────────────────────────────────────────────────────────────
class TMUtilityApp extends StatelessWidget {
  const TMUtilityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TM Utility',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00B4D8)),
        scaffoldBackgroundColor: AppColors.background,
        textTheme: GoogleFonts.interTextTheme(),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}

// ─── Dashboard Screen ─────────────────────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  static const _channel = MethodChannel('com.tmutility.app/ussd');

  bool _isRefreshing = false;
  String _lastUpdated = '14:30';
  int _selectedSimSlot = 0; // Dual SIM Support (0: SIM 1, 1: SIM 2)

  // Dynamic State Variables (Both Remaining & Dynamic Totals)
  double _balance = 45.70;

  double _internetRemainingMB = 2150.4; // 2.1 GB
  double _internetTotalGB = 5.0;

  int _minutesRemaining = 120;
  int _minutesTotal = 300;

  int _smsRemaining = 50;
  int _smsTotal = 100;

  Completer<void>? _refreshCompleter;
  Timer? _timeoutTimer;

  late AnimationController _spinController;
  late Animation<double> _spinAnimation;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _spinAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _spinController, curve: Curves.easeInOut),
    );

    // Native Silent SMS Listener Setup
    _channel.setMethodCallHandler(_nativeMethodCallHandler);
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _spinController.dispose();
    super.dispose();
  }

  Future<dynamic> _nativeMethodCallHandler(MethodCall call) async {
    if (call.method == 'onSmsReceived') {
      final Map<dynamic, dynamic> args = call.arguments;
      final String body = args['body'] ?? '';
      _processIncomingText(body);
    }
  }

  void _processIncomingText(String text) {
    final parsed = TMParser.parseMessage(text);
    final now = TimeOfDay.now();
    final timestamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    bool updated = false;

    setState(() {
      if (parsed.balance != null) {
        _balance = parsed.balance!;
        updated = true;
      }
      if (parsed.internetMB != null) {
        _internetRemainingMB = parsed.internetMB!;
        updated = true;
      }
      if (parsed.totalInternetGB != null) {
        _internetTotalGB = parsed.totalInternetGB!;
        updated = true;
      }
      if (parsed.minutes != null) {
        _minutesRemaining = parsed.minutes!;
        updated = true;
      }
      if (parsed.totalMinutes != null) {
        _minutesTotal = parsed.totalMinutes!;
        updated = true;
      }
      if (parsed.sms != null) {
        _smsRemaining = parsed.sms!;
        updated = true;
      }
      if (parsed.totalSMS != null) {
        _smsTotal = parsed.totalSMS!;
        updated = true;
      }
      if (updated) {
        _lastUpdated = timestamp;
      }
    });

    if (updated && _refreshCompleter != null && !_refreshCompleter!.isCompleted) {
      _refreshCompleter!.complete();
    }
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;

    // 1. Permission Check for SMS & Phone
    final smsStatus = await Permission.sms.request();
    final phoneStatus = await Permission.phone.request();

    if (!smsStatus.isGranted || !phoneStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('İzinler verilmedi. USSD ve SMS işlemi gerçekleştirilemiyor.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    setState(() => _isRefreshing = true);
    _spinController.repeat();

    _refreshCompleter = Completer<void>();

    // 2. Flexible 12-second Timeout
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 12), () {
      if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
        _refreshCompleter!.completeError('TIMEOUT');
      }
    });

    try {
      // 3. Trigger USSD *0801# and *0805# with dual SIM support
      final String? ussd1 = await _channel.invokeMethod<String>(
        'sendUSSD',
        {'ussdCode': '*0801#', 'simSlot': _selectedSimSlot},
      );
      if (ussd1 != null && ussd1.isNotEmpty) {
        _processIncomingText(ussd1);
      }

      await Future.delayed(const Duration(milliseconds: 300));

      final String? ussd2 = await _channel.invokeMethod<String>(
        'sendUSSD',
        {'ussdCode': '*0805#', 'simSlot': _selectedSimSlot},
      );
      if (ussd2 != null && ussd2.isNotEmpty) {
        _processIncomingText(ussd2);
      }

      // Await completion (either instant operator response or timeout)
      await _refreshCompleter!.future;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white),
                SizedBox(width: 8),
                Text('Veriler güncellendi!'),
              ],
            ),
            backgroundColor: Color(0xFF00B4D8),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (e == 'TIMEOUT' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Operatörden yanıt alınamadı. Lütfen tekrar deneyiniz.'),
            backgroundColor: Colors.deepOrange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      _timeoutTimer?.cancel();
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
        _spinController.stop();
        _spinController.reset();
      }
    }
  }

  void _toggleSimSlot() {
    setState(() {
      _selectedSimSlot = _selectedSimSlot == 0 ? 1 : 0;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Varsayılan hat: SIM ${_selectedSimSlot + 1} seçildi'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double internetGB = _internetRemainingMB / 1024.0;
    final double internetProgress =
        _internetTotalGB > 0 ? (internetGB / _internetTotalGB).clamp(0.0, 1.0) : 0.0;
    final double minutesProgress =
        _minutesTotal > 0 ? (_minutesRemaining / _minutesTotal).clamp(0.0, 1.0) : 0.0;
    final double smsProgress =
        _smsTotal > 0 ? (_smsRemaining / _smsTotal).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TopBar(
                selectedSimSlot: _selectedSimSlot,
                onSimToggle: _toggleSimSlot,
              ),
              const SizedBox(height: 16),
              Text(
                'Hoş geldiňiz!',
                style: GoogleFonts.inter(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMid,
                ),
              ),
              const SizedBox(height: 20),
              _BalanceCard(balance: _balance, simSlot: _selectedSimSlot),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _UtilityCard(
                      icon: Icons.cloud_outlined,
                      iconColor: AppColors.ringInternet,
                      label: 'Internet',
                      valueText: '${internetGB.toStringAsFixed(1)} GB',
                      subText: '/ ${_internetTotalGB.toStringAsFixed(0)} GB',
                      progress: internetProgress,
                      ringColor: AppColors.ringInternet,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _UtilityCard(
                      icon: Icons.phone_outlined,
                      iconColor: AppColors.ringMinutes,
                      label: 'Minut',
                      valueText: '$_minutesRemaining',
                      subText: '/ $_minutesTotal min',
                      progress: minutesProgress,
                      ringColor: AppColors.ringMinutes,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _UtilityCard(
                      icon: Icons.mail_outline_rounded,
                      iconColor: AppColors.ringSMS,
                      label: 'SMS',
                      valueText: '$_smsRemaining',
                      subText: '/ $_smsTotal SMS',
                      progress: smsProgress,
                      ringColor: AppColors.ringSMS,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 36),
              _RefreshButton(
                isRefreshing: _isRefreshing,
                spinAnimation: _spinAnimation,
                onTap: _handleRefresh,
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  'Soňky güncelleme: $_lastUpdated',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textLight,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Top Bar ──────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final int selectedSimSlot;
  final VoidCallback onSimToggle;

  const _TopBar({
    required this.selectedSimSlot,
    required this.onSimToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: AppColors.mainGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gradEnd.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  'TM',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'TM Utility',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
        Row(
          children: [
            // Dual SIM Badge Switcher
            GestureDetector(
              onTap: onSimToggle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.sim_card_outlined,
                      size: 16,
                      color: AppColors.ringInternet,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'SIM ${selectedSimSlot + 1}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.settings_outlined,
                color: AppColors.textMid,
                size: 20,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Balance Card ─────────────────────────────────────────────────────────────
class _BalanceCard extends StatelessWidget {
  final double balance;
  final int simSlot;
  const _BalanceCard({required this.balance, required this.simSlot});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppColors.mainGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.gradEnd.withValues(alpha: 0.45),
            blurRadius: 28,
            spreadRadius: 0,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: AppColors.gradStart.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(
              right: -30,
              top: -20,
              child: _BokehCircle(size: 140, opacity: 0.12),
            ),
            Positioned(
              left: -20,
              bottom: -30,
              child: _BokehCircle(size: 110, opacity: 0.10),
            ),
            Positioned(
              right: 60,
              bottom: 10,
              child: _BokehCircle(size: 60, opacity: 0.08),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Esasy balans',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        '+993 6${simSlot + 5} xxxxxx',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.70),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text(
                    '${balance.toStringAsFixed(2)} TMT',
                    style: GoogleFonts.inter(
                      fontSize: 46,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.0,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.trending_up_rounded,
                        color: Colors.white.withValues(alpha: 0.70),
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Esasy hasap (SIM ${simSlot + 1})',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.70),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BokehCircle extends StatelessWidget {
  final double size;
  final double opacity;
  const _BokehCircle({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
  }
}

// ─── Utility Card ─────────────────────────────────────────────────────────────
class _UtilityCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String valueText;
  final String subText;
  final double progress;
  final Color ringColor;

  const _UtilityCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.valueText,
    required this.subText,
    required this.progress,
    required this.ringColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 70,
            height: 70,
            child: CustomPaint(
              painter: _RingPainter(
                progress: progress,
                ringColor: ringColor,
                trackColor: ringColor.withValues(alpha: 0.12),
                strokeWidth: 7,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      valueText,
                      style: GoogleFonts.inter(
                        fontSize: valueText.length > 4 ? 11 : 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                        height: 1.1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      subText,
                      style: GoogleFonts.inter(
                        fontSize: 8,
                        color: AppColors.textMid,
                        height: 1.2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Ring Painter ─────────────────────────────────────────────────────────────
class _RingPainter extends CustomPainter {
  final double progress;
  final Color ringColor;
  final Color trackColor;
  final double strokeWidth;

  const _RingPainter({
    required this.progress,
    required this.ringColor,
    required this.trackColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    if (progress > 0) {
      final progressPaint = Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: -math.pi / 2 + 2 * math.pi * progress,
          colors: [ringColor, ringColor.withValues(alpha: 0.7)],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ─── Refresh Button ───────────────────────────────────────────────────────────
class _RefreshButton extends StatelessWidget {
  final bool isRefreshing;
  final Animation<double> spinAnimation;
  final VoidCallback onTap;

  const _RefreshButton({
    required this.isRefreshing,
    required this.spinAnimation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          gradient: AppColors.btnGradient,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: AppColors.gradEnd.withValues(alpha: isRefreshing ? 0.55 : 0.40),
              blurRadius: isRefreshing ? 22 : 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: spinAnimation,
              builder: (_, child) => Transform.rotate(
                angle: spinAnimation.value * 2 * math.pi,
                child: child,
              ),
              child: const Icon(
                Icons.sync_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              isRefreshing ? 'Yüklenýär...' : 'Yenile',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
