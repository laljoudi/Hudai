// Public utility functions that parse Arabic spoken digit words and
// Eastern Arabic numerals (٠–٩) into Western digits, and normalise
// Saudi mobile-number prefixes (+966 / 00966 / 966) into the canonical
// 05xxxxxxxx form.
//
// The same logic is currently embedded as private top-level helpers in
// both setup_controller.dart and settings_emergency_controller.dart.
// This file mirrors that logic so it can be unit-tested, and is also the
// source the manual-entry validation now delegates to.

/// Converts a string of Arabic spoken digit words and/or Eastern Arabic
/// numerals (٠–٩) into a string of Western digits, then normalises any
/// Saudi mobile prefix to the canonical 05xxxxxxxx form.
String arabicSpeechToDigits(String text) {
  if (text.isEmpty) return '';

  const eastern = '٠١٢٣٤٥٦٧٨٩';
  const arabicWordToDigit = <String, String>{
    // 0
    'صفر': '0', 'سفر': '0', 'صفرا': '0', 'صفرة': '0',
    // 1
    'واحد': '1', 'وحد': '1', 'وحدة': '1', 'واحدة': '1',
    // 2
    'اثنان': '2', 'اثنين': '2', 'إثنان': '2', 'إثنين': '2',
    'تنين': '2', 'اتنين': '2', 'إتنين': '2', 'ثنين': '2',
    // 3
    'ثلاثة': '3', 'ثلاث': '3', 'تلاتة': '3', 'تلاثة': '3', 'ثلاثه': '3',
    // 4
    'أربعة': '4', 'اربعة': '4', 'أربع': '4', 'اربع': '4', 'اربعه': '4',
    // 5
    'خمسة': '5', 'خمس': '5', 'خمسه': '5',
    // 6
    'ستة': '6', 'ست': '6', 'سته': '6', 'ستا': '6',
    // 7
    'سبعة': '7', 'سبع': '7', 'سبعه': '7',
    // 8
    'ثمانية': '8', 'ثماني': '8', 'تمانية': '8', 'تماني': '8', 'ثمانيه': '8',
    // 9
    'تسعة': '9', 'تسع': '9', 'تسعه': '9',
  };

  final buf = StringBuffer();
  final arab = RegExp(r'[؀-ۿ]');
  int i = 0;
  while (i < text.length) {
    final ch = text[i];

    // ASCII digit
    if (RegExp(r'[0-9]').hasMatch(ch)) {
      buf.write(ch);
      i++;
      continue;
    }

    // Eastern Arabic numeral
    final ei = eastern.indexOf(ch);
    if (ei >= 0) {
      buf.write(ei);
      i++;
      continue;
    }

    // Arabic word — accumulate consecutive Arabic letters and look up
    if (arab.hasMatch(ch)) {
      var j = i;
      while (j < text.length && arab.hasMatch(text[j])) {
        j++;
      }
      final word = text.substring(i, j);
      final mapped = arabicWordToDigit[word];
      if (mapped != null) buf.write(mapped);
      i = j;
      continue;
    }

    i++;
  }

  return normalizeSaudiNumber(buf.toString());
}

/// Normalises a digit string to the canonical Saudi mobile format
/// 05xxxxxxxx by stripping country-code prefixes (00966 / 966), adding
/// a leading zero when the user dropped it, or extracting an embedded
/// 05xxxxxxxx pattern from a longer noisy string.
String normalizeSaudiNumber(String d) {
  if (d.startsWith('00966')) {
    d = '0${d.substring(5)}';
  } else if (d.startsWith('966')) {
    d = '0${d.substring(3)}';
  }

  if (d.length == 9 && d.startsWith('5')) d = '0$d';

  if (d.length != 10) {
    final m = RegExp(r'05\d{8}').firstMatch(d);
    if (m != null) return m.group(0)!;
  }

  return d;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Manual emergency-number entry: Arabic-numeral normalisation + validation.
//
//  Used by the manual (keyboard) entry path of both the Setup and the
//  Settings → Edit Emergency Number screens. Unlike [normalizeSaudiNumber],
//  these helpers do NOT strip country codes or add a leading zero — manual
//  entry is held to the strict 05XXXXXXXX rule. Their job beyond that strict
//  check is to accept Eastern Arabic (٠–٩) and Persian/Urdu (۰–۹) numerals,
//  which a user may type on an Arabic keyboard.
//
//  NOTE: the original controller logic used `replaceAll(RegExp(r'[^\d]'), '')`.
//  In Dart, `\d` matches ASCII [0-9] ONLY, so Eastern Arabic numerals were
//  treated as non-digits and stripped to an empty string — making a perfectly
//  valid Arabic-typed number fail validation. These helpers fix that.
// ─────────────────────────────────────────────────────────────────────────────

/// Converts Eastern Arabic-Indic (٠–٩, U+0660–U+0669) and Extended
/// Arabic-Indic / Persian-Urdu (۰–۹, U+06F0–U+06F9) numerals to their ASCII
/// equivalents. Every other character is passed through unchanged.
String normalizeArabicDigits(String input) {
  if (input.isEmpty) return input;
  final buffer = StringBuffer();
  for (final code in input.runes) {
    if (code >= 0x0660 && code <= 0x0669) {
      buffer.write(code - 0x0660); // ٠–٩
    } else if (code >= 0x06F0 && code <= 0x06F9) {
      buffer.write(code - 0x06F0); // ۰–۹
    } else {
      buffer.writeCharCode(code);
    }
  }
  return buffer.toString();
}

/// Normalises Arabic numerals, trims, and strips every non-digit character
/// (spaces, symbols, letters), returning the bare digit string. Returns ""
/// for null/blank input.
String extractEmergencyDigits(String? raw) {
  final normalized = normalizeArabicDigits((raw ?? '').trim());
  return normalized.replaceAll(RegExp(r'[^0-9]'), '');
}

/// True when [raw] resolves to a canonical Saudi mobile number: exactly
/// 10 digits beginning with "05" (after Arabic-numeral normalisation and
/// non-digit stripping).
bool isValidEmergencyNumber(String? raw) {
  return RegExp(r'^05\d{8}$').hasMatch(extractEmergencyDigits(raw));
}
