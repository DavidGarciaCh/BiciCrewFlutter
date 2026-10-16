import 'package:flutter/material.dart';
import '../profile/profile_page.dart';
import '../tracking/activity_page.dart';
import '../tracking/data/sync_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    SyncService.instance.start();
  }

  static const _pages = <Widget>[
    _Placeholder('Inicio (feed)', Icons.home_outlined),
    ActivityPage(),
    _Placeholder('Comunidades', Icons.groups_outlined),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack mantiene el estado de cada pestaña al cambiar entre ellas
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Inicio'),
          NavigationDestination(
              icon: Icon(Icons.directions_bike_outlined),
              selectedIcon: Icon(Icons.directions_bike),
              label: 'Actividad'),
          NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups),
              label: 'Comunidades'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Perfil'),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final String title;
  final IconData icon;
  const _Placeholder(this.title, this.icon);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const Text('Próximamente'),
        ],
      ),
    );
  }
}