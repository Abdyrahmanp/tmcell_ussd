import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
      home: const AppInitializer(),
    );
  }
}

// ─── App Initializer ─────────────────────────────────────────────────────────
class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  bool _isLoading = true;
  bool _hasPhoneNumber = false;

  @override
  void initState() {
    super.initState();
    _checkSavedPhone();
  }

  Future<void> _checkSavedPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('phone_number');
    if (mounted) {
      setState(() {
        _hasPhoneNumber = phone != null && phone.trim().isNotEmpty;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.ringInternet),
        ),
      );
    }

    if (!_hasPhoneNumber) {
      return const OnboardingScreen();
    }

    return const MainNavigationScreen();
  }
}

// ─── Mandatory Full-Screen Onboarding ─────────────────────────────────────────
class OnboardingScreen extends StatefulWidget {
  final bool isEditing;
  final int? forcedSimSlot; // Gerekiyor SIM slot (e.g. SIM 2 üçin = 1)
  const OnboardingScreen({super.key, this.isEditing = false, this.forcedSimSlot});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _phoneController =
      TextEditingController(text: '+993 6');
  String? _errorMessage;
  bool _isVerifying = false;
  static const _channel = MethodChannel('com.tmutility.app/ussd');

  @override
  void initState() {
    super.initState();
    _loadCurrentPhone();
  }

  Future<void> _loadCurrentPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final slot = widget.forcedSimSlot ?? 0;
    final saved = slot == 1
        ? prefs.getString('phone_number_sim_1')
        : prefs.getString('phone_number');
    if (saved != null && saved.isNotEmpty && mounted) {
      _phoneController.text = saved;
    }
  }

  Future<void> _submitPhoneNumber({bool skipVerification = false}) async {
    if (_isVerifying) return;

    var text = _phoneController.text.trim();
    // Normalize spaces and non-digit characters except leading +
    var rawDigits = text.replaceAll(RegExp(r'\D'), '');

    // Format to clean +993XXXXXXXX
    String cleanNumber;
    if (rawDigits.startsWith('993')) {
      cleanNumber = '+$rawDigits';
    } else {
      cleanNumber = '+993$rawDigits';
    }

    // Validate TM CELL & Turkmenistan Phone prefixes: +993 (61..65, 71) XXXXXX
    final regex = RegExp(r'^\+993(6[1-5]|71)\d{6}$');

    if (!regex.hasMatch(cleanNumber)) {
      setState(() {
        _errorMessage = 'Haýyş, dogry TM CELL nomerini giriziň (+993 61-65 we 71 XXXXXX)';
      });
      return;
    }

    // Formatted presentation: +993 6X XXXXXX
    final formatted = '+993 ${cleanNumber.substring(4, 6)} ${cleanNumber.substring(6)}';

    setState(() {
      _errorMessage = null;
      _isVerifying = true;
    });

    String? detectedMsisdn;

    if (!skipVerification && !kIsWeb && Platform.isAndroid) {
      try {
        final smsStatus = await Permission.sms.request();
        final phoneStatus = await Permission.phone.request();

        if (smsStatus.isGranted && phoneStatus.isGranted) {
          final ussdResponse = await _channel.invokeMethod<String>(
            'sendUSSD',
            {'ussdCode': '*222#', 'simSlot': 0},
          );
          if (ussdResponse != null && ussdResponse.isNotEmpty) {
            detectedMsisdn = TMParser.parseMSISDN(ussdResponse);
          }
        }
      } catch (e) {
        debugPrint('USSD *222# verification error: $e');
      }
    }

    if (mounted) {
      setState(() {
        _isVerifying = false;
      });
    }

    // Smart comparison
    if (detectedMsisdn != null && detectedMsisdn.isNotEmpty) {
      final digitsEntered = cleanNumber.replaceAll(RegExp(r'\D'), '');
      final digitsDetected = detectedMsisdn.replaceAll(RegExp(r'\D'), '');

      final entered8 = digitsEntered.length >= 8
          ? digitsEntered.substring(digitsEntered.length - 8)
          : digitsEntered;
      final detected8 = digitsDetected.length >= 8
          ? digitsDetected.substring(digitsDetected.length - 8)
          : digitsDetected;

      if (entered8 != detected8) {
        if (!mounted) return;
        final shouldProceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                SizedBox(width: 8),
                Text('Nomer Gabat Gelmedi'),
              ],
            ),
            content: Text(
              'Girizilen nomer: $formatted\nSIM-den okalan nomer: $detectedMsisdn\n\nNomeriňiz SIM kart bilen gabat gelmedi! Ýöne test üçin dowam edip bilersiňiz.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Ýalňyşlygy Düzet'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B4D8),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Ýene-de Dowam Et (Test)'),
              ),
            ],
          ),
        );

        if (shouldProceed != true) {
          return;
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Nomer dogry tassyklandy! (SIM MSISDN: $detectedMsisdn)'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final simSlot = widget.forcedSimSlot ?? 0;
    await prefs.setString('phone_number_sim_$simSlot', formatted);
    if (simSlot == 0) {
      await prefs.setString('phone_number', formatted);
    }

    if (widget.isEditing) {
      if (mounted) Navigator.pop(context, formatted);
    } else {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
        );
      }
    }
  }

  Future<void> _skipWithoutNumber() async {
    final simSlot = widget.forcedSimSlot ?? 0;
    final demoNumber = '+993 6${simSlot == 1 ? '1' : '5'} 000000';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('phone_number_sim_$simSlot', demoNumber);
    if (simSlot == 0) {
      await prefs.setString('phone_number', demoNumber);
    }

    if (widget.isEditing || widget.forcedSimSlot != null) {
      if (mounted) Navigator.pop(context, demoNumber);
    } else {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.isEditing)
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.pop(context),
                )
              else
                const SizedBox(height: 16),

              const Spacer(flex: 1),

              // Logo & Icon
              Center(
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    gradient: AppColors.mainGradient,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.gradEnd.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      'TM',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 32,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Title & Description
              Text(
                widget.isEditing ? 'Nomeri üýtgetmek' : 'Hoş geldiňiz!',
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.isEditing
                    ? 'Täze TM CELL telefon belgiňizi giriziň.'
                    : 'TM Utility hyzmatyndan peýdalanmak üçin telefon belgiňizi giriziň (*222# arkaly barlandyrylýar).',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: AppColors.textMid,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),

              // Input field
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [LengthLimitingTextInputFormatter(16)],
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                    letterSpacing: 0.5,
                  ),
                  decoration: InputDecoration(
                    prefixIcon: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Icon(
                        Icons.phone_android_rounded,
                        color: AppColors.ringInternet,
                        size: 24,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 50),
                    hintText: '+993 65 123456',
                    hintStyle: GoogleFonts.inter(
                      color: AppColors.textLight,
                      fontWeight: FontWeight.w400,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 18),
                  ),
                  onChanged: (val) {
                    if (_errorMessage != null) {
                      setState(() => _errorMessage = null);
                    }
                    final rawDigits = val.replaceAll(RegExp(r'\D'), '');
                    final clean = rawDigits.startsWith('993') ? '+$rawDigits' : '+993$rawDigits';
                    final regex = RegExp(r'^\+993(6[1-5]|71)\d{6}$');
                    if (regex.hasMatch(clean) && !_isVerifying) {
                      _submitPhoneNumber();
                    }
                  },
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Colors.redAccent, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.inter(
                          color: Colors.redAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const Spacer(flex: 2),

              // Submit Button with Loading Indicator during *222# USSD check
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _isVerifying ? null : () => _submitPhoneNumber(),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: AppColors.btnGradient,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gradEnd.withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Container(
                      alignment: Alignment.center,
                      child: _isVerifying
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'SIM Barlaanýar (*222#)...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  widget.isEditing ? 'Ýatda saklaň' : 'Dowam et (*222#)',
                                  style: GoogleFonts.inter(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Skip without number button (Test convenience)
              Center(
                child: TextButton(
                  onPressed: _skipWithoutNumber,
                  child: Text(
                    'Nomersiz geç (Test üçin)',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.textMid,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
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
  String _phoneNumber = '';
  String _autoRefreshFreq = 'Her 6 sagatdan'; // Auto refresh frequency

  // Dynamic State Variables (Both Remaining & Dynamic Totals)
  double _balance = 45.70;

  double _internetRemainingMB = 2150.4; // MB
  double _internetTotalMB = 5120.0;     // MB (5 GB → 5120 MB)

  int _minutesRemaining = 120;
  int _minutesTotal = 300;

  int _smsRemaining = 50;
  int _smsTotal = 100;

  TMPackageType? _detectedPackage;

  Completer<void>? _refreshCompleter;
  Timer? _timeoutTimer;
  Timer? _autoRefreshTimer;
  int _signalLevel = 4; // 0 to 4 cellular signal strength bars

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

    _loadPreferences();

    // Native Silent SMS Listener Setup
    _channel.setMethodCallHandler(_nativeMethodCallHandler);
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _timeoutTimer?.cancel();
    _spinController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSim = prefs.getInt('sim_slot') ?? 0;
    final savedFreq = prefs.getString('auto_refresh_freq') ?? 'Her 6 sagatdan';

    _selectedSimSlot = savedSim;
    _autoRefreshFreq = savedFreq;

    _startAutoRefreshTimer(savedFreq);
    _getSignalStrength();
    await _loadSimData(savedSim);
  }

  Future<void> _getSignalStrength() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final int? level = await _channel.invokeMethod<int>(
          'getSignalStrength',
          {'simSlot': _selectedSimSlot},
        );
        if (level != null && mounted) {
          setState(() {
            _signalLevel = level.clamp(0, 4);
          });
        }
      } catch (e) {
        debugPrint('Signal strength error: $e');
      }
    }
  }

  void _startAutoRefreshTimer(String freq) {
    _autoRefreshTimer?.cancel();
    if (freq == 'Öçürilen') return;

    Duration duration;
    switch (freq) {
      case 'Her 6 sagatdan':
        duration = const Duration(hours: 6);
        break;
      case 'Her 12 sagatdan':
        duration = const Duration(hours: 12);
        break;
      case 'Her 24 sagatdan':
        duration = const Duration(hours: 24);
        break;
      default:
        duration = const Duration(hours: 6);
    }

    _autoRefreshTimer = Timer.periodic(duration, (_) {
      if (mounted && !_isRefreshing) {
        _handleRefresh();
      }
    });
  }

  Future<void> _loadSimData(int slot) async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _selectedSimSlot = slot;
      _phoneNumber = prefs.getString('phone_number_sim_$slot') ??
          (slot == 0
              ? (prefs.getString('phone_number') ?? '+993 65 123456')
              : '+993 61 987654');

      _balance = prefs.getDouble('balance_sim_$slot') ?? (slot == 0 ? 45.70 : 15.00);
      _internetRemainingMB =
          prefs.getDouble('internet_rem_sim_$slot') ?? (slot == 0 ? 2150.4 : 1024.0);
      _internetTotalMB =
          prefs.getDouble('internet_tot_mb_sim_$slot') ?? (slot == 0 ? 5120.0 : 3072.0);
      _minutesRemaining =
          prefs.getInt('minutes_rem_sim_$slot') ?? (slot == 0 ? 120 : 45);
      _minutesTotal =
          prefs.getInt('minutes_tot_sim_$slot') ?? (slot == 0 ? 300 : 100);
      _smsRemaining =
          prefs.getInt('sms_rem_sim_$slot') ?? (slot == 0 ? 50 : 20);
      _smsTotal =
          prefs.getInt('sms_tot_sim_$slot') ?? (slot == 0 ? 100 : 50);
      _lastUpdated =
          prefs.getString('last_updated_sim_$slot') ?? (slot == 0 ? '--:--' : '--:--');
      _detectedPackage = null;
    });
  }

  Future<void> _saveSimData(int slot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('phone_number_sim_$slot', _phoneNumber);
    await prefs.setDouble('balance_sim_$slot', _balance);
    await prefs.setDouble('internet_rem_sim_$slot', _internetRemainingMB);
    await prefs.setDouble('internet_tot_mb_sim_$slot', _internetTotalMB);
    await prefs.setInt('minutes_rem_sim_$slot', _minutesRemaining);
    await prefs.setInt('minutes_tot_sim_$slot', _minutesTotal);
    await prefs.setInt('sms_rem_sim_$slot', _smsRemaining);
    await prefs.setInt('sms_tot_sim_$slot', _smsTotal);
    await prefs.setString('last_updated_sim_$slot', _lastUpdated);
    if (slot == 0) {
      await prefs.setString('phone_number', _phoneNumber);
    }
  }

  Future<void> _saveSimSlot(int slot) async {
    if (slot == 1) {
      // SIM 2 saýlananda hasaba alnan nomer barlanýar
      final prefs = await SharedPreferences.getInstance();
      final sim2Number = prefs.getString('phone_number_sim_1') ?? '';
      final hasNumber = sim2Number.isNotEmpty &&
          sim2Number != '+993 61 987654' &&
          !sim2Number.contains('000000');

      if (!hasNumber && mounted) {
        final shouldContinue = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.sim_card_alert_rounded,
                    color: Colors.orangeAccent),
                const SizedBox(width: 8),
                Text(
                  'SIM 2 Nomeri Ýok',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700, fontSize: 17),
                ),
              ],
            ),
            content: Text(
              'Heniz SIM 2 nomerini girizmediňiz.\nHaýyş, SIM 2 telefon belgiňizi giriziň.',
              style: GoogleFonts.inter(fontSize: 14, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Ýatyr',
                    style: GoogleFonts.inter(
                        color: AppColors.textMid, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B4D8),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Nomer Giriziň',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );

        if (shouldContinue == true && mounted) {
          final newPhone = await Navigator.push<String>(
            context,
            MaterialPageRoute(
              builder: (_) => const OnboardingScreen(
                isEditing: true,
                forcedSimSlot: 1,
              ),
            ),
          );
          if (newPhone != null && newPhone.isNotEmpty) {
            final p = await SharedPreferences.getInstance();
            await p.setString('phone_number_sim_1', newPhone);
          }
        }
        return; // Geçişi iptal et, SIM 1-e gal
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sim_slot', slot);
    await _loadSimData(slot);
    _getSignalStrength();
  }

  Future<void> _saveAutoRefreshFreq(String freq) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auto_refresh_freq', freq);
    setState(() {
      _autoRefreshFreq = freq;
    });
    _startAutoRefreshTimer(freq);
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
      if (parsed.totalInternetMB != null) {
        _internetTotalMB = parsed.totalInternetMB!;
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
      // Package totals override
      if (parsed.detectedPackage != null) {
        _detectedPackage = parsed.detectedPackage;
        _internetTotalMB = parsed.detectedPackage!.totalInternetMB;
        _minutesTotal = parsed.detectedPackage!.totalMinutes;
        _smsTotal = parsed.detectedPackage!.totalSMS;
        updated = true;
      }
      if (updated) {
        _lastUpdated = timestamp;
      }
    });

    // Paket tapylandygy barada habar ber
    if (parsed.detectedPackage != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.inventory_2_outlined,
                  color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                '${parsed.detectedPackage!.displayName} paketi anyklandy!',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          backgroundColor: AppColors.ringMinutes,
          duration: const Duration(seconds: 3),
        ),
      );
    }

    if (updated) {
      _saveSimData(_selectedSimSlot);
      if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
        _refreshCompleter!.complete();
      }
    }
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;

    final bool isRealAndroidDevice = !kIsWeb && Platform.isAndroid;

    if (!isRealAndroidDevice) {
      await _runMockSimulation();
      return;
    }

    // 1. Permission Check for SMS & Phone on Android
    final smsStatus = await Permission.sms.request();
    final phoneStatus = await Permission.phone.request();

    if (!smsStatus.isGranted || !phoneStatus.isGranted) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                SizedBox(width: 8),
                Text('Rugsat Talap Edilýär'),
              ],
            ),
            content: const Text(
              'Awtomatiki USSD arama we SMS maglumatlaryny okamak üçin Jaň (CALL_PHONE) we SMS (RECEIVE_SMS) rugsatlary zerurdyr. Haýyş, sazlamalardan rugsat beriň.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Ýatyr'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  openAppSettings();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B4D8),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Sazlamalara Git'),
              ),
            ],
          ),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rugsatlar berilmedi. USSD hem-de SMS amaly ýerine ýetirilip bilinmedi.'),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() => _isRefreshing = true);
    _spinController.repeat();

    _refreshCompleter = Completer<void>();

    // Status notification for user when USSD is triggered
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'USSD tetiklenýär (SIM ${_selectedSimSlot + 1}: *0800# we *0805#)...',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF00B4D8),
          duration: const Duration(seconds: 4),
        ),
      );
    }

    // 2. Flexible 12-second Timeout
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 12), () {
      if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
        _refreshCompleter!.completeError('TIMEOUT');
      }
    });

    try {
      // 3. Trigger USSD *0800# (Balance Pop-up) & *0805# (SMS Details) with dual SIM support
      final String? ussd1 = await _channel.invokeMethod<String>(
        'sendUSSD',
        {'ussdCode': '*0800#', 'simSlot': _selectedSimSlot},
      );
      if (ussd1 != null && ussd1.isNotEmpty) {
        _processIncomingText(ussd1);
      }

      await Future.delayed(const Duration(milliseconds: 500));

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
                Text('Maglumatlar täzelendi!'),
              ],
            ),
            backgroundColor: Color(0xFF00B4D8),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } on MissingPluginException catch (_) {
      await _runMockSimulation();
      return;
    } catch (e) {
      if (e == 'TIMEOUT' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Operatordan jogap alynmady. Täzeden synanyşyň.'),
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

  /// Smooth 2-second Mock Simulation for Emulators / PC testing
  Future<void> _runMockSimulation() async {
    setState(() => _isRefreshing = true);
    _spinController.repeat();

    await Future.delayed(const Duration(milliseconds: 2000));

    final now = TimeOfDay.now();
    final timestamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    setState(() {
      _isRefreshing = false;
      _lastUpdated = timestamp;
      _balance = (45.70 - (math.Random().nextDouble() * 0.4)).clamp(0.0, 999.0);
    });
    _saveSimData(_selectedSimSlot);
    _spinController.stop();
    _spinController.reset();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white),
              SizedBox(width: 8),
              Text('Maglumatlar täzelendi! (Synag režeýimi)'),
            ],
          ),
          backgroundColor: Color(0xFF00B4D8),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showSettingsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Sazlamalar',
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Option 1: Change Phone Number via Full Screen Onboarding
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.ringInternet.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.phone_rounded,
                          color: AppColors.ringInternet),
                    ),
                    title: Text(
                      'Nomeri üýtgetmek',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                    subtitle: Text(
                      _phoneNumber,
                      style: GoogleFonts.inter(
                        color: AppColors.textMid,
                        fontSize: 13,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      Navigator.pop(context);
                      final newPhone = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const OnboardingScreen(isEditing: true),
                        ),
                      );
                      if (newPhone != null && newPhone.isNotEmpty) {
                        setState(() {
                          _phoneNumber = newPhone;
                        });
                      }
                    },
                  ),
                  const Divider(height: 24),

                  // Option 2: Select SIM Slot
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.ringMinutes.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.sim_card_outlined,
                          color: AppColors.ringMinutes),
                    ),
                    title: Text(
                      'SIM karta saýlamak',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                    subtitle: Text(
                      'Häzirki saýlanan: SIM ${_selectedSimSlot + 1}',
                      style: GoogleFonts.inter(
                        color: AppColors.textMid,
                        fontSize: 13,
                      ),
                    ),
                    trailing: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('SIM 1')),
                        ButtonSegment(value: 1, label: Text('SIM 2')),
                      ],
                      selected: {_selectedSimSlot},
                      onSelectionChanged: (Set<int> newSelection) {
                        final selected = newSelection.first;
                        _saveSimSlot(selected);
                        setModalState(() {});
                        setState(() {});
                      },
                    ),
                  ),
                  const Divider(height: 24),

                  // Option 3: Auto Refresh Frequency
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.ringSMS.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.update_rounded,
                          color: AppColors.ringSMS),
                    ),
                    title: Text(
                      'Awtomatiki täzelenme',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                    subtitle: Text(
                      _autoRefreshFreq,
                      style: GoogleFonts.inter(
                        color: AppColors.textMid,
                        fontSize: 13,
                      ),
                    ),
                    trailing: DropdownButton<String>(
                      value: _autoRefreshFreq,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(
                          value: 'Her 6 sagatdan',
                          child: Text('Her 6 sagatdan'),
                        ),
                        DropdownMenuItem(
                          value: 'Her 12 sagatdan',
                          child: Text('Her 12 sagatdan'),
                        ),
                        DropdownMenuItem(
                          value: 'Her 24 sagatdan',
                          child: Text('Her 24 sagatdan'),
                        ),
                        DropdownMenuItem(
                          value: 'Öçürilen',
                          child: Text('Öçürilen'),
                        ),
                      ],
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          _saveAutoRefreshFreq(newValue);
                          setModalState(() {});
                          setState(() {});
                        }
                      },
                    ),
                  ),
                  const Divider(height: 24),

                  // Option 4: About App
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.gradStart.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.info_outline_rounded,
                          color: AppColors.gradStart),
                    ),
                    title: Text(
                      'Programma barada',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                    subtitle: Text(
                      'TM Utility v1.0.0 • TM CELL Hyzmaty',
                      style: GoogleFonts.inter(
                        color: AppColors.textMid,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    // Internet – MB galan, total GB görkezilýär
    final double internetProgress =
        _internetTotalMB > 0
            ? (_internetRemainingMB / _internetTotalMB).clamp(0.0, 1.0)
            : 0.0;
    final double minutesProgress =
        _minutesTotal > 0 ? (_minutesRemaining / _minutesTotal).clamp(0.0, 1.0) : 0.0;
    final double smsProgress =
        _smsTotal > 0 ? (_smsRemaining / _smsTotal).clamp(0.0, 1.0) : 0.0;

    // Internet display helpers – galan MB, jemi GB görgüsinde
    final int remMB = _internetRemainingMB.round().clamp(0, 999999);
    final int totMB = _internetTotalMB.round().clamp(0, 999999);
    final String internetSubText = _internetTotalMB >= 1024
        ? '/ ${(_internetTotalMB / 1024.0).toStringAsFixed(0)} GB'
        : '/ $totMB MB';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _handleRefresh,
          color: AppColors.ringInternet,
          backgroundColor: Colors.white,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TopBar(
                  selectedSimSlot: _selectedSimSlot,
                  signalLevel: _signalLevel,
                  onOpenSettings: _showSettingsBottomSheet,
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
                _BalanceCard(
                  balance: _balance,
                  phoneNumber: _phoneNumber,
                  simSlot: _selectedSimSlot,
                  detectedPackage: _detectedPackage,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _UtilityCard(
                        icon: Icons.cloud_outlined,
                        iconColor: AppColors.ringInternet,
                        label: 'Internet',
                        valueText: '$remMB MB',
                        subText: internetSubText,
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
                const SizedBox(height: 32),
                _RefreshButton(
                  isRefreshing: _isRefreshing,
                  spinAnimation: _spinAnimation,
                  onTap: _handleRefresh,
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    'Soňky täzelenme: $_lastUpdated • Swiping down (ýokary serpmek) täzeleýär',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textLight,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Top Bar ──────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final int selectedSimSlot;
  final int signalLevel;
  final VoidCallback onOpenSettings;

  const _TopBar({
    required this.selectedSimSlot,
    required this.signalLevel,
    required this.onOpenSettings,
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
            _SignalIndicator(level: signalLevel),
            const SizedBox(width: 8),
            // SIM Badge Indicator
            Container(
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
                  const Icon(
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
            const SizedBox(width: 8),
            // Settings Button
            GestureDetector(
              onTap: onOpenSettings,
              child: Container(
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
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Cellular Signal Strength Indicator ─────────────────────────────────────────
class _SignalIndicator extends StatelessWidget {
  final int level; // 0 to 4 signal strength bars
  const _SignalIndicator({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(4, (i) {
              final barHeight = 5.0 + (i * 3.0);
              final active = i < level;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                width: 3,
                height: barHeight,
                decoration: BoxDecoration(
                  color: active ? AppColors.ringInternet : AppColors.textLight.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
          const SizedBox(width: 4),
          Text(
            'Signal',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Balance Card ─────────────────────────────────────────────────────────────
class _BalanceCard extends StatelessWidget {
  final double balance;
  final String phoneNumber;
  final int simSlot;
  final TMPackageType? detectedPackage;

  const _BalanceCard({
    required this.balance,
    required this.phoneNumber,
    required this.simSlot,
    this.detectedPackage,
  });

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
            const Positioned(
              right: -30,
              top: -20,
              child: _BokehCircle(size: 140, opacity: 0.12),
            ),
            const Positioned(
              left: -20,
              bottom: -30,
              child: _BokehCircle(size: 110, opacity: 0.10),
            ),
            const Positioned(
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
                        phoneNumber.isNotEmpty ? phoneNumber : 'Nomeri giriziň',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w500,
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
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
                      if (detectedPackage != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            detectedPackage!.displayName,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
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
              isRefreshing ? 'Ýüklenýär...' : 'Täzele',
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

// ─── Internet Package Card ───────────────────────────────────────────────────
class _InternetPackageCard extends StatelessWidget {
  final InternetPackage package;
  final VoidCallback onTap;

  const _InternetPackageCard({
    required this.package,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.ringInternet.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        package.badgeText,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ringInternet,
                        ),
                      ),
                    ),
                    Text(
                      '${package.priceTMT.toStringAsFixed(0)} TMT',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: AppColors.btnGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.gradEnd.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.wifi_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            package.name,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark,
                            ),
                          ),
                          Text(
                            package.dataSize,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ringInternet,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.ringInternet.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Satyn Al (${package.ussdCode})',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ringInternet,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.touch_app_rounded,
                        size: 14,
                        color: AppColors.ringInternet,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Main Navigation Screen (Bottom Tab Shell) ───────────────────────────────
class MainNavigationScreen extends StatefulWidget {
  final int initialIndex;
  const MainNavigationScreen({super.key, this.initialIndex = 0});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const DashboardScreen(),
      const InternetPackagesScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          selectedItemColor: AppColors.ringInternet,
          unselectedItemColor: AppColors.textMid,
          elevation: 0,
          backgroundColor: Colors.white,
          selectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12),
          unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 12),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_rounded),
              label: 'Esasy',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.wifi_protected_setup_rounded),
              label: 'Internet Bukjalary',
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Internet Packages Screen ────────────────────────────────────────────────
class InternetPackagesScreen extends StatefulWidget {
  const InternetPackagesScreen({super.key});

  @override
  State<InternetPackagesScreen> createState() => _InternetPackagesScreenState();
}

class _InternetPackagesScreenState extends State<InternetPackagesScreen> {
  static const _channel = MethodChannel('com.tmutility.app/ussd');
  int _selectedSimSlot = 0;

  @override
  void initState() {
    super.initState();
    _loadSimSlot();
  }

  Future<void> _loadSimSlot() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _selectedSimSlot = prefs.getInt('sim_slot') ?? 0;
      });
    }
  }

  Future<void> _showInternetPurchaseConfirmationDialog(InternetPackage pkg) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titlePadding: EdgeInsets.zero,
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          title: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFD90429), Color(0xFFEF233C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'ÜNS BERIŇ!',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Balansdan Töleg Kesiler',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 10),
              RichText(
                text: TextSpan(
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppColors.textDark,
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(text: 'Siz '),
                    TextSpan(
                      text: '${pkg.name} (${pkg.dataSize})',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.gradMid),
                    ),
                    const TextSpan(text: ' internet paketi birikdirýärsiňiz.\n\nHasabyňyzdan derrew '),
                    TextSpan(
                      text: '${pkg.priceTMT.toStringAsFixed(0)} TMT',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFD90429)),
                    ),
                    const TextSpan(text: ' aýrylar! Dowam etmek isleýärsiňizmi?'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.textLight.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sim_card_outlined, size: 18, color: AppColors.ringInternet),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'USSD: ${pkg.ussdCode} (SIM ${_selectedSimSlot + 1})',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMid,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                side: const BorderSide(color: AppColors.textLight),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: Text(
                'Ýatyr',
                style: GoogleFonts.inter(
                  color: AppColors.textMid,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00B4D8),
                foregroundColor: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              child: Text(
                'Tassykla we Birikdir',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await _executeInternetPurchase(pkg);
    }
  }

  Future<void> _executeInternetPurchase(InternetPackage pkg) async {
    final bool isRealAndroidDevice = !kIsWeb && Platform.isAndroid;

    if (!isRealAndroidDevice) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${pkg.name} (${pkg.dataSize}) haýyş gowşuryldy! (${pkg.ussdCode} SIM ${_selectedSimSlot + 1})',
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF00B4D8),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final smsStatus = await Permission.sms.request();
    final phoneStatus = await Permission.phone.request();

    if (!smsStatus.isGranted || !phoneStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rugsat berilmedi. Hyzmat birikdirilip bilinmedi.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    try {
      final String? response = await _channel.invokeMethod<String>(
        'sendUSSD',
        {'ussdCode': pkg.ussdCode, 'simSlot': _selectedSimSlot},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response != null && response.isNotEmpty
                  ? response
                  : '${pkg.name} sargydy ugradyldy (${pkg.ussdCode})',
            ),
            backgroundColor: const Color(0xFF00B4D8),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Säwlik ýüze çykdy: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                        child: const Icon(Icons.wifi_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Internet Bukjalary',
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                          Text(
                            '*0850* hyzmaty arkaly',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.textMid,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Bir Basymda',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: AppColors.ringInternet, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'USSD koduny manuel yazmazdan, bir basymda hazır internet bukjalaryny ygtybarly birikdiriň.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textMid,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tmInternetPackages.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1.10,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemBuilder: (context, index) {
                  final pkg = tmInternetPackages[index];
                  return _InternetPackageCard(
                    package: pkg,
                    onTap: () => _showInternetPurchaseConfirmationDialog(pkg),
                  );
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
