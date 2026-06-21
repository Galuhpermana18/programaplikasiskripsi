import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import 'ui/splashscrean.dart';
import 'ui/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseDatabase.instance.setPersistenceEnabled(true);
  FirebaseDatabase.instance.setPersistenceCacheSizeBytes(10000000);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Air Fresh',
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
      onGenerateRoute: (settings) {
        if (settings.name == '/home') {
          final arguments = settings.arguments;
          final deviceId = arguments is Map
              ? arguments['deviceId']?.toString() ?? ''
              : '';
          return MaterialPageRoute<void>(
            builder: (_) => HomePage(deviceId: deviceId),
          );
        }
        return null;
      },
    );
  }
}
