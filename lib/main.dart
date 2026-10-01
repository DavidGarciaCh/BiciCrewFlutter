import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
  runApp(const BiciCrewApp());
}

// Acceso rápido al cliente de Supabase desde cualquier archivo
final supabase = Supabase.instance.client;

class BiciCrewApp extends StatelessWidget {
  const BiciCrewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BiciCrew',
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: const Scaffold(
        body: Center(child: Text('BiciCrew: Supabase inicializado')),
      ),
    );
  }
}