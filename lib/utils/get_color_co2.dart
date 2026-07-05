import 'package:flutter/material.dart';

class Eco2Status {
  final String label;
  final Color color;

  const Eco2Status(this.label, this.color);
}

Eco2Status getEco2Status(int eco2) {
  if (eco2 < 0) {
    return const Eco2Status('NULL', Colors.blue);
  } else if (eco2 <= 1000) {
    return const Eco2Status('BAIK', Color(0xFF00E400));
  } else if (eco2 <= 1500) {
    return const Eco2Status('SEDANG', Color(0xFFFFFF00));
  } else {
    return const Eco2Status('BURUK', Color(0xFFFF0000));
  }
}

Color getEco2Color(int eco2) => getEco2Status(eco2).color;
