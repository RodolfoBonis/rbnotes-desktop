import 'package:flutter/material.dart';

/// Reserves the space where the macOS traffic-light buttons (close / minimize /
/// zoom) sit, without drawing anything.
///
/// The app used to paint fake dots here; the window now shows the real native
/// buttons (positioned natively at the top-left inset — see
/// `MainFlutterWindow.swift`). This widget keeps the surrounding layout
/// (the sidebar/login/onboarding headers) spaced exactly as before so the
/// native buttons land in the right place.
class TrafficLights extends StatelessWidget {
  const TrafficLights({super.key});

  /// Footprint of the three 12px dots with two 8px gaps (12*3 + 8*2).
  static const double width = 52;
  static const double height = 12;

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: width, height: height);
}
