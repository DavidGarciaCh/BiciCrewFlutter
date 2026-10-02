import 'package:flutter/material.dart';
import '../../core/supabase_config.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<Map<String, dynamic>> _loadProfile() {
    return supabase
        .from('profiles')
        .select()
        .eq('id', supabase.auth.currentUser!.id)
        .single();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BiciCrew'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => supabase.auth.signOut(),
          ),
        ],
      ),
      body: Center(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _loadProfile(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const CircularProgressIndicator();
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Error al cargar el perfil:\n${snapshot.error}'),
              );
            }
            final p = snapshot.data!;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/logo.png', height: 100),
                const SizedBox(height: 16),
                Text('Hola, ${p['first_name']} ${p['last_name']}',
                    style: Theme.of(context).textTheme.headlineSmall),
                Text('${p['city']}, ${p['country']}  ·  rol: ${p['role']}'),
              ],
            );
          },
        ),
      ),
    );
  }
}