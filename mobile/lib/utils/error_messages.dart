import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/app_error.dart';

/// Centralized error message mapping so UI can show friendly text instead of raw technical errors.
/// No UI/layout or business logic here.
class ErrorMessages {
  /// Friendly, contextual message for any error object.
  static String userFriendlyMessage(Object error) {
    // Firebase (Firestore/Auth/etc.)
    if (error is FirebaseException) {
      final code = error.code.toLowerCase();
      final msg = (error.message ?? '').toLowerCase();

      switch (code) {
        case 'permission-denied':
          return "You don't have permission for this action. Contact your admin.";
        case 'unavailable':
        case 'network-request-failed':
          return "No internet connection. Please check your network.";
        case 'deadline-exceeded':
          return "Request timed out. Try again.";
        case 'not-found':
          return "The item was not found. It may have been removed.";
        default:
          if (msg.contains('network') ||
              msg.contains('socket') ||
              msg.contains('connection')) {
            return "No internet connection. Please check your network.";
          }
          if (msg.contains('timeout') || code.contains('timeout')) {
            return "Request timed out. Try again.";
          }
          return "Something went wrong. Try again.";
      }
    }

    // Domain error wrapper
    if (error is AppError) {
      // Keep existing userMessage if it's already friendly.
      return error.userMessage;
    }

    // Common low-level issues
    if (error is TimeoutException) {
      return "Request timed out. Try again.";
    }
    if (error is SocketException) {
      return "No internet connection. Please check your network.";
    }

    // String or anything else
    final asString = error.toString().trim();
    if (asString.toLowerCase().contains('permission')) {
      return "You don't have permission for this action. Contact your admin.";
    }
    if (asString.toLowerCase().contains('network') ||
        asString.toLowerCase().contains('socket') ||
        asString.toLowerCase().contains('connection')) {
      return "No internet connection. Please check your network.";
    }
    if (asString.toLowerCase().contains('timeout')) {
      return "Request timed out. Try again.";
    }

    return "Something went wrong. Try again.";
  }

  /// Retry label for any error. Empty string = no retry button.
  static String retryLabel(Object error) {
    if (error is FirebaseException) {
      final code = error.code.toLowerCase();
      if (code == 'permission-denied') {
        // User cannot fix this from the app; no retry label.
        return "";
      }
      return "Retry";
    }
    // For all other cases, allow retry.
    return "Retry";
  }
}

// ---------------------------------------------------------------------------
// Backwards-compatible helpers used across the app
// ---------------------------------------------------------------------------

/// Legacy helper: friendly message for FirebaseException only.
String userFriendlyMessage(FirebaseException e) =>
    ErrorMessages.userFriendlyMessage(e);

/// Legacy helper: friendly message for any error object.
String userFriendlyMessageFromError(dynamic e) =>
    ErrorMessages.userFriendlyMessage(e ?? Object());

/// Legacy helper: retry label for any error object (empty string = no retry).
String errorActionLabelFromError(dynamic e) =>
    ErrorMessages.retryLabel(e ?? Object());

/// Legacy helper: retry label for FirebaseException (null maps to no button).
String? errorActionLabel(FirebaseException e) {
  final label = ErrorMessages.retryLabel(e);
  return label.isEmpty ? null : label;
}
