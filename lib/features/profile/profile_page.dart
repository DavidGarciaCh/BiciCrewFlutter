import 'package:flutter/material.dart';
import '../../core/supabase_config.dart';
import '../../core/utils.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _country = TextEditingController();
  final _city = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String _role = 'user';

  String get _uid => supabase.auth.currentUser!.id;
  String get _email => supabase.auth.currentUser?.email ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_firstName, _lastName, _phone, _country, _city]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await supabase.from('profiles').select().eq('id', _uid).single();
      _firstName.text = p['first_name'] ?? '';
      _lastName.text = p['last_name'] ?? '';
      _phone.text = p['phone'] ?? '';
      _country.text = p['country'] ?? '';
      _city.text = p['city'] ?? '';
      _role = p['role'] ?? 'user';
    } catch (e) {
      if (mounted) showMessage(context, 'No se pudo cargar el perfil', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await supabase.from('profiles').update({
        'first_name': _firstName.text.trim(),
        'last_name': _lastName.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'country': _country.text.trim(),
        'city': _city.text.trim(),
      }).eq('id', _uid);
      if (mounted) showMessage(context, 'Perfil actualizado');
    } catch (e) {
      if (mounted) showMessage(context, 'No se pudo guardar: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null;

  Widget _field(TextEditingController c, String label,
      {String? Function(String?)? validator, TextInputType? type}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: type,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final initial =
        _firstName.text.isNotEmpty ? _firstName.text[0].toUpperCase() : '?';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              CircleAvatar(radius: 40, child: Text(initial, style: const TextStyle(fontSize: 32))),
              const SizedBox(height: 8),
              Text(_email),
              Text('Rol: $_role', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 24),
              _field(_firstName, 'Nombres', validator: _required),
              _field(_lastName, 'Apellidos', validator: _required),
              _field(_phone, 'Teléfono', type: TextInputType.phone),
              _field(_country, 'País', validator: _required),
              _field(_city, 'Ciudad', validator: _required),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Guardar cambios'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar sesión'),
                  onPressed: () => supabase.auth.signOut(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}