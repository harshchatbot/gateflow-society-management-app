import 'package:csv/csv.dart';

/// Validation result for CSV parsing
class ValidationResult {
  final List<Map<String, String>> validRows;
  final List<RowError> invalidRows;
  final List<String> warnings;
  final int totalRows;
  final bool hasValidRows;

  ValidationResult({
    required this.validRows,
    required this.invalidRows,
    required this.warnings,
    required this.totalRows,
  }) : hasValidRows = validRows.isNotEmpty;

  int get validCount => validRows.length;
  int get invalidCount => invalidRows.length;
}

/// Error information for an invalid CSV row
class RowError {
  final int rowNumber; // 1-based (header is row 1, first data row is row 2)
  final String reason;
  final List<String> rawRow;

  RowError({
    required this.rowNumber,
    required this.reason,
    required this.rawRow,
  });
}

/// CSV Validators for Guards and Residents
class CsvValidators {
  // Expected headers (normalized to lowercase)
  static const List<String> _guardRequiredHeaders = ['name', 'email', 'phone'];
  static const List<String> _guardOptionalHeaders = ['shift', 'employeeid'];
  
  static const List<String> _residentRequiredHeaders = ['name', 'email', 'phone', 'flatno'];
  static const List<String> _residentOptionalHeaders = ['tower', 'role'];

  /// Normalize header: lowercase, trim, remove BOM
  static String normalizeHeader(String header) {
    return header.trim().toLowerCase().replaceAll(RegExp(r'^\uFEFF'), ''); // Remove BOM
  }

  /// Check if a row is completely empty
  static bool isRowEmpty(List<dynamic> row) {
    return row.every((cell) => cell.toString().trim().isEmpty);
  }

  /// Validate email format (simple regex)
  static bool isValidEmail(String email) {
    if (email.trim().isEmpty) return false;
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    return emailRegex.hasMatch(email.trim());
  }

  /// Normalize and validate phone number (India format)
  /// Accepts: 10 digits, or +91 followed by 10 digits
  /// Returns normalized phone (10 digits) or null if invalid
  static String? normalizePhone(String phone) {
    final cleaned = phone.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
    
    // Remove +91 prefix if present
    if (cleaned.startsWith('+91')) {
      final withoutPrefix = cleaned.substring(3);
      if (withoutPrefix.length == 10 && RegExp(r'^\d{10}$').hasMatch(withoutPrefix)) {
        return withoutPrefix;
      }
    }
    
    // Check if it's exactly 10 digits
    if (cleaned.length == 10 && RegExp(r'^\d{10}$').hasMatch(cleaned)) {
      return cleaned;
    }
    
    return null;
  }

  /// Normalize flat number (trim, normalize spaces)
  static String normalizeFlatNo(String flatNo) {
    return flatNo.trim().replaceAll(RegExp(r'\s+'), ' '); // Normalize multiple spaces to single space
  }

  /// Validate role (allowed values)
  static bool isValidRole(String? role) {
    if (role == null || role.trim().isEmpty) return true; // Optional, default to resident
    final normalized = role.trim().toLowerCase();
    return ['resident', 'owner', 'tenant'].contains(normalized);
  }

  /// Parse CSV text into rows
  static List<List<dynamic>> _parseCsv(String csvText) {
    try {
      return const CsvToListConverter().convert(csvText);
    } catch (e) {
      throw Exception('Failed to parse CSV: $e');
    }
  }

  /// Validate Guards CSV
  static ValidationResult validateGuardsCsv(String csvText) {
    final validRows = <Map<String, String>>[];
    final invalidRows = <RowError>[];
    final warnings = <String>[];
    final seenEmails = <String>{}; // Track duplicate emails (case-insensitive)
    final seenPhones = <String>{}; // Track duplicate phones

    try {
      final csvData = _parseCsv(csvText);
      
      if (csvData.isEmpty) {
        return ValidationResult(
          validRows: [],
          invalidRows: [RowError(
            rowNumber: 0,
            reason: 'CSV file is empty',
            rawRow: [],
          )],
          warnings: [],
          totalRows: 0,
        );
      }

      // Parse headers
      final rawHeaders = csvData[0].map((h) => h.toString()).toList();
      final normalizedHeaders = rawHeaders.map(normalizeHeader).toList();
      
      // Validate required headers
      final missingHeaders = <String>[];
      for (final requiredHeader in _guardRequiredHeaders) {
        if (!normalizedHeaders.contains(requiredHeader)) {
          missingHeaders.add(requiredHeader);
        }
      }

      if (missingHeaders.isNotEmpty) {
        return ValidationResult(
          validRows: [],
          invalidRows: [RowError(
            rowNumber: 1,
            reason: 'Missing required headers: ${missingHeaders.join(", ")}',
            rawRow: rawHeaders,
          )],
          warnings: [],
          totalRows: csvData.length - 1, // Exclude header
        );
      }

      // Process data rows
      for (int i = 1; i < csvData.length; i++) {
        final row = csvData[i];
        final rowNumber = i + 1; // 1-based for user display

        // Skip empty rows
        if (isRowEmpty(row)) {
          continue;
        }

        // Build row map with normalized headers
        final rowMap = <String, String>{};
        for (int j = 0; j < normalizedHeaders.length && j < row.length; j++) {
          rowMap[normalizedHeaders[j]] = row[j].toString().trim();
        }

        // Validate required fields
        final errors = <String>[];

        // Name validation
        final name = rowMap['name'] ?? '';
        if (name.isEmpty) {
          errors.add('Name is required');
        }

        // Email validation
        final email = rowMap['email'] ?? '';
        if (email.isEmpty) {
          errors.add('Email is required');
        } else if (!isValidEmail(email)) {
          errors.add('Invalid email format');
        } else {
          final emailLower = email.toLowerCase();
          if (seenEmails.contains(emailLower)) {
            errors.add('Duplicate email (already used in this file)');
          } else {
            seenEmails.add(emailLower);
          }
        }

        // Phone validation
        final phone = rowMap['phone'] ?? '';
        if (phone.isEmpty) {
          errors.add('Phone is required');
        } else {
          final normalizedPhone = normalizePhone(phone);
          if (normalizedPhone == null) {
            errors.add('Invalid phone format (must be 10 digits or +91 followed by 10 digits)');
          } else {
            if (seenPhones.contains(normalizedPhone)) {
              errors.add('Duplicate phone number (already used in this file)');
            } else {
              seenPhones.add(normalizedPhone);
              rowMap['phone'] = normalizedPhone; // Store normalized phone
            }
          }
        }

        // If errors found, add to invalid rows
        if (errors.isNotEmpty) {
          invalidRows.add(RowError(
            rowNumber: rowNumber,
            reason: errors.join('; '),
            rawRow: row.map((e) => e.toString()).toList(),
          ));
          continue;
        }

        // Row is valid
        validRows.add(rowMap);
      }

      return ValidationResult(
        validRows: validRows,
        invalidRows: invalidRows,
        warnings: warnings,
        totalRows: csvData.length - 1, // Exclude header
      );
    } catch (e) {
      return ValidationResult(
        validRows: [],
        invalidRows: [RowError(
          rowNumber: 0,
          reason: 'CSV parsing error: $e',
          rawRow: [],
        )],
        warnings: [],
        totalRows: 0,
      );
    }
  }

  /// Validate Residents CSV
  static ValidationResult validateResidentsCsv(String csvText) {
    final validRows = <Map<String, String>>[];
    final invalidRows = <RowError>[];
    final warnings = <String>[];
    final seenEmails = <String>{}; // Track duplicate emails (case-insensitive)
    final seenPhones = <String>{}; // Track duplicate phones
    final seenFlatNos = <String>{}; // Track duplicate flat numbers (for warnings)

    try {
      final csvData = _parseCsv(csvText);
      
      if (csvData.isEmpty) {
        return ValidationResult(
          validRows: [],
          invalidRows: [RowError(
            rowNumber: 0,
            reason: 'CSV file is empty',
            rawRow: [],
          )],
          warnings: [],
          totalRows: 0,
        );
      }

      // Parse headers
      final rawHeaders = csvData[0].map((h) => h.toString()).toList();
      final normalizedHeaders = rawHeaders.map(normalizeHeader).toList();
      
      // Validate required headers
      final missingHeaders = <String>[];
      for (final requiredHeader in _residentRequiredHeaders) {
        if (!normalizedHeaders.contains(requiredHeader)) {
          missingHeaders.add(requiredHeader);
        }
      }

      if (missingHeaders.isNotEmpty) {
        return ValidationResult(
          validRows: [],
          invalidRows: [RowError(
            rowNumber: 1,
            reason: 'Missing required headers: ${missingHeaders.join(", ")}',
            rawRow: rawHeaders,
          )],
          warnings: [],
          totalRows: csvData.length - 1, // Exclude header
        );
      }

      // Process data rows
      for (int i = 1; i < csvData.length; i++) {
        final row = csvData[i];
        final rowNumber = i + 1; // 1-based for user display

        // Skip empty rows
        if (isRowEmpty(row)) {
          continue;
        }

        // Build row map with normalized headers
        final rowMap = <String, String>{};
        for (int j = 0; j < normalizedHeaders.length && j < row.length; j++) {
          rowMap[normalizedHeaders[j]] = row[j].toString().trim();
        }

        // Validate required fields
        final errors = <String>[];

        // Name validation
        final name = rowMap['name'] ?? '';
        if (name.isEmpty) {
          errors.add('Name is required');
        }

        // Email validation
        final email = rowMap['email'] ?? '';
        if (email.isEmpty) {
          errors.add('Email is required');
        } else if (!isValidEmail(email)) {
          errors.add('Invalid email format');
        } else {
          final emailLower = email.toLowerCase();
          if (seenEmails.contains(emailLower)) {
            errors.add('Duplicate email (already used in this file)');
          } else {
            seenEmails.add(emailLower);
          }
        }

        // Phone validation
        final phone = rowMap['phone'] ?? '';
        if (phone.isEmpty) {
          errors.add('Phone is required');
        } else {
          final normalizedPhone = normalizePhone(phone);
          if (normalizedPhone == null) {
            errors.add('Invalid phone format (must be 10 digits or +91 followed by 10 digits)');
          } else {
            if (seenPhones.contains(normalizedPhone)) {
              errors.add('Duplicate phone number (already used in this file)');
            } else {
              seenPhones.add(normalizedPhone);
              rowMap['phone'] = normalizedPhone; // Store normalized phone
            }
          }
        }

        // FlatNo validation
        final flatNo = rowMap['flatno'] ?? '';
        if (flatNo.isEmpty) {
          errors.add('Flat No is required');
        } else {
          final normalizedFlatNo = normalizeFlatNo(flatNo);
          rowMap['flatno'] = normalizedFlatNo; // Store normalized flatNo
          
          // Check for duplicate flat numbers (warning, not error)
          if (seenFlatNos.contains(normalizedFlatNo.toUpperCase())) {
            warnings.add('Row $rowNumber: Duplicate flat number "$normalizedFlatNo" (may be intentional for multiple residents)');
          } else {
            seenFlatNos.add(normalizedFlatNo.toUpperCase());
          }
        }

        // Role validation (optional)
        final role = rowMap['role'];
        if (role != null && role.isNotEmpty && !isValidRole(role)) {
          errors.add('Invalid role (must be: resident, owner, or tenant)');
        } else if (role == null || role.isEmpty) {
          rowMap['role'] = 'resident'; // Set default
        } else {
          rowMap['role'] = role.trim().toLowerCase(); // Normalize role
        }

        // Tower is optional, just normalize if present
        if (rowMap.containsKey('tower') && rowMap['tower'] != null) {
          rowMap['tower'] = rowMap['tower']!.trim();
        }

        // If errors found, add to invalid rows
        if (errors.isNotEmpty) {
          invalidRows.add(RowError(
            rowNumber: rowNumber,
            reason: errors.join('; '),
            rawRow: row.map((e) => e.toString()).toList(),
          ));
          continue;
        }

        // Row is valid
        validRows.add(rowMap);
      }

      return ValidationResult(
        validRows: validRows,
        invalidRows: invalidRows,
        warnings: warnings,
        totalRows: csvData.length - 1, // Exclude header
      );
    } catch (e) {
      return ValidationResult(
        validRows: [],
        invalidRows: [RowError(
          rowNumber: 0,
          reason: 'CSV parsing error: $e',
          rawRow: [],
        )],
        warnings: [],
        totalRows: 0,
      );
    }
  }
}
