class TMData {
  final double? balance;
  final double? internetMB;
  final double? totalInternetMB;
  final int? minutes;
  final int? totalMinutes;
  final int? sms;
  final int? totalSMS;

  TMData({
    this.balance,
    this.internetMB,
    this.totalInternetMB,
    this.minutes,
    this.totalMinutes,
    this.sms,
    this.totalSMS,
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
  }) {
    return TMData(
      balance: balance ?? this.balance,
      internetMB: internetMB ?? this.internetMB,
      totalInternetMB: totalInternetMB ?? this.totalInternetMB,
      minutes: minutes ?? this.minutes,
      totalMinutes: totalMinutes ?? this.totalMinutes,
      sms: sms ?? this.sms,
      totalSMS: totalSMS ?? this.totalSMS,
    );
  }

  @override
  String toString() {
    return 'TMData(balance: $balance TMT, internet: $internetMB/${totalInternetMB}MB, minutes: $minutes/${totalMinutes}min, sms: $sms/$totalSMS)';
  }
}

class TMParser {
  /// Parses balance from USSD/SMS text with word boundaries
  /// e.g., "Sizin balansynyz: 45.70 TMT."
  static double? parseBalance(String text) {
    final regex = RegExp(r'\bbalansynyz:\s*([\d\.]+)\s*TMT\b', caseSensitive: false);
    final match = regex.firstMatch(text);
    if (match != null && match.groupCount >= 1) {
      return double.tryParse(match.group(1)!);
    }
    final fallback = RegExp(r'\b([\d\.]+)\s*TMT\b', caseSensitive: false);
    final fMatch = fallback.firstMatch(text);
    if (fMatch != null && fMatch.groupCount >= 1) {
      return double.tryParse(fMatch.group(1)!);
    }
    return null;
  }

  /// Parses total package minutes
  /// e.g., "Sowgat 500 min pakedyn gutarmagyna..."
  static int? parseTotalMinutes(String text) {
    if (!text.toLowerCase().contains('min')) return null;
    final regex = RegExp(r'\b(\d+)\s*min\b.*?\bpakedyn\b', caseSensitive: false);
    final match = regex.firstMatch(text);
    if (match != null && match.groupCount >= 1) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  /// Parses remaining minutes from SMS text
  /// e.g. "Sowgat 500 min pakedyn gutarmagyna 465 min ya-da 29 galdy"
  static int? parseMinutes(String text) {
    if (!text.toLowerCase().contains('min')) return null;

    final gutarmagynaRegex = RegExp(r'\bgutarmagyna\s*(\d+)\s*min\b', caseSensitive: false);
    final gMatch = gutarmagynaRegex.firstMatch(text);
    if (gMatch != null) {
      return int.tryParse(gMatch.group(1)!);
    }

    final yadaRegex = RegExp(r'\b(\d+)\s*min\s+ya-da\b', caseSensitive: false);
    final yMatch = yadaRegex.firstMatch(text);
    if (yMatch != null) {
      return int.tryParse(yMatch.group(1)!);
    }

    return null;
  }

  /// Parses total package SMS limit
  /// e.g., "Sowgat 200 sms pakedyn gutarmagyna..."
  static int? parseTotalSMS(String text) {
    if (!text.toLowerCase().contains('sms') && !text.toLowerCase().contains('sany')) {
      return null;
    }
    final regex = RegExp(r'\b(\d+)\s*(?:sms|sany)\b.*?\bpakedyn\b', caseSensitive: false);
    final match = regex.firstMatch(text);
    if (match != null && match.groupCount >= 1) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  /// Parses remaining SMS count from SMS text
  /// e.g. "Sowgat 200 sms pakedyn gutarmagyna 187 sany ya-da 29 galdy"
  static int? parseSMS(String text) {
    if (!text.toLowerCase().contains('sany')) return null;

    final gutarmagynaRegex = RegExp(r'\bgutarmagyna\s*(\d+)\s*sany\b', caseSensitive: false);
    final gMatch = gutarmagynaRegex.firstMatch(text);
    if (gMatch != null) {
      return int.tryParse(gMatch.group(1)!);
    }

    final yadaRegex = RegExp(r'\b(\d+)\s*sany\s+ya-da\b', caseSensitive: false);
    final yMatch = yadaRegex.firstMatch(text);
    if (yMatch != null) {
      return int.tryParse(yMatch.group(1)!);
    }

    return null;
  }

  /// Parses total package internet capacity in MB
  /// e.g. "Sowgat 5 GB pakedyn..." or "sow 1000 mb pakedyn..."
  static double? parseTotalInternetMB(String text) {
    final totalGBMatch = RegExp(r'\b([\d\.]+)\s*GB\b.*?\bpakedyn\b', caseSensitive: false).firstMatch(text);
    if (totalGBMatch != null && totalGBMatch.groupCount >= 1) {
      final gb = double.tryParse(totalGBMatch.group(1)!);
      if (gb != null) return gb * 1024.0;
    }

    final totalMBMatch = RegExp(r'\b([\d\.]+)\s*MB\b.*?\bpakedyn\b', caseSensitive: false).firstMatch(text);
    if (totalMBMatch != null && totalMBMatch.groupCount >= 1) {
      return double.tryParse(totalMBMatch.group(1)!);
    }

    return null;
  }

  /// Parses remaining internet data in MB from SMS text
  /// e.g. "sow 1000 mb pakedyn gutarmagyna 150 MB ya-da 29 galdy" or "2.1 GB"
  static double? parseInternetMB(String text) {
    final gutarmagynaGB = RegExp(r'\bgutarmagyna\s*([\d\.]+)\s*GB\b', caseSensitive: false);
    final gGBMatch = gutarmagynaGB.firstMatch(text);
    if (gGBMatch != null && gGBMatch.groupCount >= 1) {
      final gb = double.tryParse(gGBMatch.group(1)!);
      if (gb != null) return gb * 1024.0;
    }

    final gutarmagynaMB = RegExp(r'\bgutarmagyna\s*([\d\.]+)\s*MB\b', caseSensitive: false);
    final gMBMatch = gutarmagynaMB.firstMatch(text);
    if (gMBMatch != null && gMBMatch.groupCount >= 1) {
      return double.tryParse(gMBMatch.group(1)!);
    }

    final yadaGB = RegExp(r'\b([\d\.]+)\s*GB\s+ya-da\b', caseSensitive: false);
    final yGBMatch = yadaGB.firstMatch(text);
    if (yGBMatch != null && yGBMatch.groupCount >= 1) {
      final gb = double.tryParse(yGBMatch.group(1)!);
      if (gb != null) return gb * 1024.0;
    }

    final yadaMB = RegExp(r'\b([\d\.]+)\s*MB\s+ya-da\b', caseSensitive: false);
    final yMBMatch = yadaMB.firstMatch(text);
    if (yMBMatch != null && yMBMatch.groupCount >= 1) {
      return double.tryParse(yMBMatch.group(1)!);
    }

    return null;
  }

  /// Parses any TM CELL message and extracts both remaining and total metrics
  static TMData parseMessage(String text) {
    return TMData(
      balance: parseBalance(text),
      minutes: parseMinutes(text),
      totalMinutes: parseTotalMinutes(text),
      sms: parseSMS(text),
      totalSMS: parseTotalSMS(text),
      internetMB: parseInternetMB(text),
      totalInternetMB: parseTotalInternetMB(text),
    );
  }
}
