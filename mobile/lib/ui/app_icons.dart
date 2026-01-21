import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Central icon registry so we never use PhosphorIconsBold.* directly in screens.
class AppIcons {
  // Core
  static const guard = PhosphorIconsBold.shieldCheck;
  static const logout = PhosphorIconsBold.signOut;
  static const visitor = PhosphorIconsBold.user;
  static const visitors = PhosphorIconsBold.users;
  static const visitorList = PhosphorIconsBold.listBullets;

  // Inputs / Actions
  static const phone = PhosphorIconsBold.phone;
  static const flat = PhosphorIconsBold.house;
  static const note = PhosphorIconsBold.notePencil;
  static const refresh = PhosphorIconsBold.arrowClockwise;
  static const delete = PhosphorIconsBold.trash;
  static const camera = PhosphorIconsBold.camera;
  static const close = PhosphorIconsBold.x;
  static const send = PhosphorIconsBold.paperPlaneTilt;

  // Visitor types
  static const guest = PhosphorIconsBold.user;
  static const delivery = PhosphorIconsBold.package;
  static const cab = PhosphorIconsBold.car;

  // Status
  static const approved = PhosphorIconsBold.checkCircle;
  static const rejected = PhosphorIconsBold.xCircle;
  static const pending = PhosphorIconsBold.clock;
  static const leave = PhosphorIconsBold.handPalm;

  // Buttons
  static const approve = PhosphorIconsBold.check;
  static const reject = PhosphorIconsBold.x;

  // Media fallback
  static const imageOff = PhosphorIconsBold.imageBroken;

  // Generic
  static const more = PhosphorIconsBold.dotsThree;
}
