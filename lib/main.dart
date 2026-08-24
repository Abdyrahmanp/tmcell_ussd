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

    return const DashboardScreen();
  }
}

// ─── Mandatory Full-Screen Onboarding ─────────────────────────────────────────
class OnboardingScreen extends StatefulWidget {
  final bool isEditing;
  const OnboardingScreen({super.key, this.isEditing = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _phoneController =
      TextEditingController(text: '+993 6');
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCurrentPhone();
  }

  Future<void> _loadCurrentPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('phone_number');
    if (saved != null && saved.isNotEmpty && mounted) {
      _phoneController.text = saved;
    }
  }

  Future<void> _submitPhoneNumber() async {
    final text = _phoneController.text.trim();
    final cleanNumber = text.replaceAll(' ', '');
    // Validate TM CELL phone number format: +993 6X XXXXXX
    final regex = RegExp(r'^\+9936[1-6]\d{6}$');

    if (!regex.hasMatch(cleanNumber)) {
      setState(() {
        _errorMessage = 'Haýyş, dogry TM CELL nomerini giriziň (+993 6X XXXXXX)';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('phone_number', text);

    if (widget.isEditing) {
      if (mounted) Navigator.pop(context, text);
    } else {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
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
                    : 'TM Utility hyzmatyndan peýdalanmak üçin telefon belgiňizi giriziň.',
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
                  onChanged: (_) {
                    if (_errorMessage != null) {
                      setState(() => _errorMessage = null);
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

              // Submit Button
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
                  onPressed: _submitPhoneNumber,
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
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.isEditing ? 'Ýatda saklaň' : 'Dowam et',
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
              const SizedBox(height: 16),
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

    _loadPreferences();

    // Native Silent SMS Listener Setup
    _channel.setMethodCallHandler(_nativeMethodCallHandler);
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _spinController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPhone = prefs.getString('phone_number');
    final savedSim = prefs.getInt('sim_slot');
    final savedFreq = prefs.getString('auto_refresh_freq');

    if (mounted) {
      setState(() {
        if (savedPhone != null && savedPhone.isNotEmpty) {
          _phoneNumber = savedPhone;
        }
        if (savedSim != null) {
          _selectedSimSlot = savedSim;
        }
        if (savedFreq != null) {
          _autoRefreshFreq = savedFreq;
        }
      });
    }
  }

  Future<void> _saveSimSlot(int slot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sim_slot', slot);
    setState(() {
      _selectedSimSlot = slot;
    });
  }

  Future<void> _saveAutoRefreshFreq(String freq) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auto_refresh_freq', freq);
    setState(() {
      _autoRefreshFreq = freq;
    });
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rugsatlar berilmedi. USSD hem-de SMS amaly ýerine ýetirilip bilinmedi.'),
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
    _spinController.stop();
    _spinController.reset();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white),
              SizedBox(width: 8),
              Text('Maglumatlar täzelendi! (Simulýasiýa)'),
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
              ),
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
                  'Soňky täzelenme: $_lastUpdated',
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
  final VoidCallback onOpenSettings;

  const _TopBar({
    required this.selectedSimSlot,
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

// ─── Balance Card ─────────────────────────────────────────────────────────────
class _BalanceCard extends StatelessWidget {
  final double balance;
  final String phoneNumber;
  final int simSlot;

  const _BalanceCard({
    required this.balance,
    required this.phoneNumber,
    required this.simSlot,
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
