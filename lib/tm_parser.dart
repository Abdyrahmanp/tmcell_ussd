// ─── TM Data Model ───────────────────────────────────────────────────────────
class TMData {
  final double? balance;
  final double? internetMB;
  final double? totalInternetMB;
  final int? minutes;
  final int? totalMinutes;
  final int? sms;
  final int? totalSMS;
  final TMPackageType? detectedPackage;

  TMData({
    this.balance,
    this.internetMB,
    this.totalInternetMB,
    this.minutes,
    this.totalMinutes,
    this.sms,
    this.totalSMS,
    this.detectedPackage,
  });

  double? get internetGB => internetMB != null ? (internetMB! / 1024.0) : null;
  double? get totalInternetGB =>
      totalInternetMB != null ? (totalInternetMB! / 1024.0) : null;

  TMData copyWith({
    double? balance,
    double? internetMB,
    double? totalInternetMB,
    int? minutes,
    int? totalMinutes,
    int? sms,
    int? totalSMS,
    TMPackageType? detectedPackage,
  }) {
    return TMData(
      balance: balance ?? this.balance,
      internetMB: internetMB ?? this.internetMB,
      totalInternetMB: totalInternetMB ?? this.totalInternetMB,
      minutes: minutes ?? this.minutes,
      totalMinutes: totalMinutes ?? this.totalMinutes,
      sms: sms ?? this.sms,
      totalSMS: totalSMS ?? this.totalSMS,
      detectedPackage: detectedPackage ?? this.detectedPackage,
    );
  }

  @override
  String toString() {
    return 'TMData(balance: $balance TMT, internet: $internetMB/${totalInternetMB}MB, minutes: $minutes/${totalMinutes}min, sms: $sms/$totalSMS, package: $detectedPackage)';
  }
}

// ─── Package Type Enum ────────────────────────────────────────────────────────
enum TMPackageType {
  sowgat500,
  sowgat1000,
  sowgat2000,
}

extension TMPackageTypeExtension on TMPackageType {
  /// Total internet limit in MB for this package
  double get totalInternetMB {
    switch (this) {
      case TMPackageType.sowgat500:
        return 150.0;
      case TMPackageType.sowgat1000:
        return 500.0;
      case TMPackageType.sowgat2000:
        return 0.0; // 2000 paketde internet ýok
    }
  }

  /// Total minute limit for this package
  int get totalMinutes {
    switch (this) {
      case TMPackageType.sowgat500:
        return 500;
      case TMPackageType.sowgat1000:
        return 1000;
      case TMPackageType.sowgat2000:
        return 2000;
    }
  }

  /// Total SMS limit for this package
  int get totalSMS {
    switch (this) {
      case TMPackageType.sowgat500:
        return 200;
      case TMPackageType.sowgat1000:
        return 300;
      case TMPackageType.sowgat2000:
        return 500;
    }
  }

  String get displayName {
    switch (this) {
      case TMPackageType.sowgat500:
        return 'Sowgat 500';
      case TMPackageType.sowgat1000:
        return 'Sowgat 1000';
      case TMPackageType.sowgat2000:
        return 'Sowgat 2000';
    }
  }
}

// ─── Ready Internet Package Model ────────────────────────────────────────────
class InternetPackage {
  final String id;
  final String name;
  final String dataSize;
  final double sizeMB;
  final double priceTMT;
  final String ussdCode;
  final String badgeText;

  const InternetPackage({
    required this.id,
    required this.name,
    required this.dataSize,
    required this.sizeMB,
    required this.priceTMT,
    required this.ussdCode,
    required this.badgeText,
  });
}

const List<InternetPackage> tmInternetPackages = [
  InternetPackage(
    id: 'net_3',
    name: 'Internet 3',
    dataSize: '50 MB',
    sizeMB: 50.0,
    priceTMT: 3.0,
    ussdCode: '*0850*3#',
    badgeText: 'Ekonom',
  ),
  InternetPackage(
    id: 'net_5',
    name: 'Internet 5',
    dataSize: '100 MB',
    sizeMB: 100.0,
    priceTMT: 5.0,
    ussdCode: '*0850*5#',
    badgeText: 'Amala Tiz',
  ),
  InternetPackage(
    id: 'net_10',
    name: 'Internet 10',
    dataSize: '250 MB',
    sizeMB: 250.0,
    priceTMT: 10.0,
    ussdCode: '*0850*10#',
    badgeText: 'Meşhur',
  ),
  InternetPackage(
    id: 'net_60',
    name: 'Internet 60',
    dataSize: '1500 MB (1.5 GB)',
    sizeMB: 1500.0,
    priceTMT: 60.0,
    ussdCode: '*0850*60#',
    badgeText: 'Iň Köp Satylýan',
  ),
  InternetPackage(
    id: 'net_160',
    name: 'Internet 160',
    dataSize: '4 GB (4096 MB)',
    sizeMB: 4096.0,
    priceTMT: 160.0,
    ussdCode: '*0850*160#',
    badgeText: 'Ulanyjy Saýlawy',
  ),
  InternetPackage(
    id: 'net_200',
    name: 'Internet 200',
    dataSize: '20 GB (20480 MB)',
    sizeMB: 20480.0,
    priceTMT: 200.0,
    ussdCode: '*0850*200#',
    badgeText: 'VIP / Uly Göwrim',
  ),
];

// ─── TM Parser ────────────────────────────────────────────────────────────────
class TMParser {
  // ── 1. Balance ──────────────────────────────────────────────────────────────
  /// Parses balance supporting both dot and comma decimal separators.
  /// e.g. "Sizin balansynyz: 45.70 TMT", "Balans: 45,70 TMT", "45.70 TMT"
  static double? parseBalance(String text) {
    // Normalize comma to dot for decimal parsing
    String normalised = text.replaceAll(',', '.');

    // Priority 1: explicit "balansynyz" label
    final labeled = RegExp(
        r'\bbalansynyz\s*:?\s*([\d]+\.[\d]+|[\d]+)\s*TMT\b',
        caseSensitive: false);
    final lm = labeled.firstMatch(normalised);
    if (lm != null) return double.tryParse(lm.group(1)!);

    // Priority 2: "Balans:" label
    final balans = RegExp(
        r'\bbalans\s*:?\s*([\d]+\.[\d]+|[\d]+)\s*TMT\b',
        caseSensitive: false);
    final bm = balans.firstMatch(normalised);
    if (bm != null) return double.tryParse(bm.group(1)!);

    // Priority 3: any X.XX TMT or X TMT
    final generic = RegExp(r'\b([\d]+\.[\d]+|[\d]+)\s*TMT\b',
        caseSensitive: false);
    final gm = generic.firstMatch(normalised);
    if (gm != null) return double.tryParse(gm.group(1)!);

    return null;
  }

  // ── 2. Package Detection ────────────────────────────────────────────────────
  /// Detects which TM CELL package is referenced in the SMS text.
  /// Matches "500 paket", "Sowgat 500", "1000 paket", "Sowgat 1000", etc.
  static TMPackageType? detectPackage(String text) {
    final lower = text.toLowerCase();

    final pkg2000 = RegExp(r'\b(?:sowgat\s*2000|2000\s*paket)\b');
    if (pkg2000.hasMatch(lower)) return TMPackageType.sowgat2000;

    final pkg1000 = RegExp(r'\b(?:sowgat\s*1000|1000\s*paket)\b');
    if (pkg1000.hasMatch(lower)) return TMPackageType.sowgat1000;

    final pkg500 = RegExp(r'\b(?:sowgat\s*500|500\s*paket)\b');
    if (pkg500.hasMatch(lower)) return TMPackageType.sowgat500;

    return null;
  }

  // ── 3. Total Minutes ────────────────────────────────────────────────────────
  /// e.g. "Sowgat 500 min pakedyn gutarmagyna..."
  static int? parseTotalMinutes(String text) {
    if (!text.toLowerCase().contains('min')) return null;
    final regex =
        RegExp(r'\b(\d+)\s*min\b.*?\bpakedyn\b', caseSensitive: false);
    final match = regex.firstMatch(text);
    if (match != null && match.groupCount >= 1) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  // ── 4. Remaining Minutes ────────────────────────────────────────────────────
  /// e.g. "Sowgat 500 min pakedyn gutarmagyna 465 min ya-da 29 galdy"
  static int? parseMinutes(String text) {
    if (!text.toLowerCase().contains('min')) return null;

    final gutarRx =
        RegExp(r'\bgutarmagyna\s*(\d+)\s*min\b', caseSensitive: false);
    final gm = gutarRx.firstMatch(text);
    if (gm != null) return int.tryParse(gm.group(1)!);

    final yadaRx = RegExp(r'\b(\d+)\s*min\s+ya-da\b', caseSensitive: false);
    final ym = yadaRx.firstMatch(text);
    if (ym != null) return int.tryParse(ym.group(1)!);

    return null;
  }

  // ── 5. Total SMS ─────────────────────────────────────────────────────────────
  /// e.g. "Sowgat 200 sms pakedyn gutarmagyna..."
  static int? parseTotalSMS(String text) {
    final lower = text.toLowerCase();
    if (!lower.contains('sms') && !lower.contains('sany')) return null;
    final regex = RegExp(r'\b(\d+)\s*(?:sms|sany)\b.*?\bpakedyn\b',
        caseSensitive: false);
    final match = regex.firstMatch(text);
    if (match != null && match.groupCount >= 1) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  // ── 6. Remaining SMS ─────────────────────────────────────────────────────────
  /// e.g. "Sowgat 200 sms pakedyn gutarmagyna 187 sany ya-da 29 galdy"
  static int? parseSMS(String text) {
    if (!text.toLowerCase().contains('sany')) return null;

    final gutarRx =
        RegExp(r'\bgutarmagyna\s*(\d+)\s*sany\b', caseSensitive: false);
    final gm = gutarRx.firstMatch(text);
    if (gm != null) return int.tryParse(gm.group(1)!);

    final yadaRx = RegExp(r'\b(\d+)\s*sany\s+ya-da\b', caseSensitive: false);
    final ym = yadaRx.firstMatch(text);
    if (ym != null) return int.tryParse(ym.group(1)!);

    return null;
  }

  // ── 7. Total Internet (MB) ───────────────────────────────────────────────────
  /// e.g. "Sowgat 5 GB pakedyn..." or "sow 1000 mb pakedyn..."
  static double? parseTotalInternetMB(String text) {
    final gbMatch = RegExp(r'\b([\d.]+)\s*GB\b.*?\bpakedyn\b',
            caseSensitive: false)
        .firstMatch(text);
    if (gbMatch != null) {
      final gb = double.tryParse(gbMatch.group(1)!);
      if (gb != null) return gb * 1024.0;
    }

    final mbMatch = RegExp(r'\b([\d.]+)\s*MB\b.*?\bpakedyn\b',
            caseSensitive: false)
        .firstMatch(text);
    if (mbMatch != null) return double.tryParse(mbMatch.group(1)!);

    return null;
  }

  // ── 8. Remaining Internet (MB) ───────────────────────────────────────────────
  /// e.g. "sow 1000 mb pakedyn gutarmagyna 150 MB ya-da 29 galdy"
  static double? parseInternetMB(String text) {
    // gutarmagyna X GB
    final gutarGB =
        RegExp(r'\bgutarmagyna\s*([\d.]+)\s*GB\b', caseSensitive: false);
    final ggm = gutarGB.firstMatch(text);
    if (ggm != null) {
      final gb = double.tryParse(ggm.group(1)!);
      if (gb != null) return gb * 1024.0;
    }

    // gutarmagyna X MB
    final gutarMB =
        RegExp(r'\bgutarmagyna\s*([\d.]+)\s*MB\b', caseSensitive: false);
    final gmm = gutarMB.firstMatch(text);
    if (gmm != null) return double.tryParse(gmm.group(1)!);

    // X GB ya-da
    final yadaGB =
        RegExp(r'\b([\d.]+)\s*GB\s+ya-da\b', caseSensitive: false);
    final ygm = yadaGB.firstMatch(text);
    if (ygm != null) {
      final gb = double.tryParse(ygm.group(1)!);
      if (gb != null) return gb * 1024.0;
    }

    // X MB ya-da
    final yadaMB =
        RegExp(r'\b([\d.]+)\s*MB\s+ya-da\b', caseSensitive: false);
    final ymm = yadaMB.firstMatch(text);
    if (ymm != null) return double.tryParse(ymm.group(1)!);

    return null;
  }

  // ── 9. MSISDN (*222#) ───────────────────────────────────────────────────────
  /// Parses phone number from *222# USSD pop-up response.
  /// e.g. "MSISDN: 99365123456", "MSISDN: 99371000000" or "MSISDN: 65123456"
  static String? parseMSISDN(String text) {
    final clean = text.replaceAll(RegExp(r'\s+|-'), '');
    final regex = RegExp(
        r'(?:MSISDN:|tel:)?(\+?993(?:6[1-5]|71)\d{6}|\b(?:6[1-5]|71)\d{6}\b)',
        caseSensitive: false);
    final match = regex.firstMatch(clean);
    if (match != null && match.groupCount >= 1) {
      String raw = match.group(1)!;
      if (!raw.startsWith('+993') && !raw.startsWith('993')) {
        raw = '+993$raw';
      } else if (raw.startsWith('993')) {
        raw = '+$raw';
      }
      return raw;
    }
    return null;
  }

  // ── 10. Full parse ───────────────────────────────────────────────────────────
  /// Parses any TM CELL message and extracts all metrics.
  /// Package totals override parsed totals when a known package is detected.
  static TMData parseMessage(String text) {
    final pkg = detectPackage(text);

    final parsedTotalInternet = parseTotalInternetMB(text);
    final parsedTotalMinutes = parseTotalMinutes(text);
    final parsedTotalSMS = parseTotalSMS(text);

    return TMData(
      balance: parseBalance(text),
      minutes: parseMinutes(text),
      // Package total overrides SMS-parsed total when package is detected
      totalMinutes: pkg != null
          ? pkg.totalMinutes
          : (parsedTotalMinutes ?? pkg?.totalMinutes),
      sms: parseSMS(text),
      totalSMS: pkg != null
          ? pkg.totalSMS
          : (parsedTotalSMS ?? pkg?.totalSMS),
      internetMB: parseInternetMB(text),
      totalInternetMB: pkg != null
          ? pkg.totalInternetMB
          : (parsedTotalInternet ?? pkg?.totalInternetMB),
      detectedPackage: pkg,
    );
  }
}
