import 'package:flutter/material.dart';

/// Config for a chip group (e.g. Cab Provider, Delivery Partner). Add entries to [visitorChipGroups] to extend.
class ChipGroupConfig {
  final String title;
  final String visitorType;
  final String storageKey;
  final String field;
  final List<String> options;
  final String defaultValue;
  final IconData icon;

  const ChipGroupConfig({
    required this.title,
    required this.visitorType,
    required this.storageKey,
    required this.field,
    required this.options,
    required this.defaultValue,
    required this.icon,
  });
}

/// Shared chip group config for visitor type (CAB, DELIVERY). Used by new visitor form and visitor details read-only display.
final List<ChipGroupConfig> visitorChipGroups = [
  const ChipGroupConfig(
    title: 'Cab Provider',
    visitorType: 'CAB',
    storageKey: 'cab',
    field: 'provider',
    options: ['Ola', 'Uber', 'Other'],
    defaultValue: 'Other',
    icon: Icons.directions_car_rounded,
  ),
  const ChipGroupConfig(
    title: 'Delivery Partner',
    visitorType: 'DELIVERY',
    storageKey: 'delivery',
    field: 'provider',
    options: [
      'Zomato',
      'Swiggy',
      'Blinkit',
      'Zepto',
      'Amazon',
      'Flipkart',
      'Dunzo',
      'Other'
    ],
    defaultValue: 'Other',
    icon: Icons.local_shipping_rounded,
  ),
];

String visitorChipSelectionKey(ChipGroupConfig g) =>
    '${g.storageKey}.${g.field}';
