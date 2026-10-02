import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_config.dart';
import '../../core/utils.dart';
import 'verify_otp_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _country = TextEditingController(text: 'Colombia');
  final _city = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _consent = false;
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    for (final c in [
      _firstName, _lastName, _email, _phone,
      _country, _city, _password, _confirm,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null;

  String? _validateEmail(String? v) {
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '');
    return ok ? null : 'Correo no válido';
  }

  String? _validatePassword(String? v) =>
      (v == null || v.length < 8) ? 'Mínimo 8 caracteres' : null;

  String? _validateConfirm(String? v) =>
      v != _password.text ? 'Las contraseñas no coinciden' : null;

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_consent) {
      showMessage(context, 'Debes aceptar el tratamiento de tus datos',
          error: true);
      return;
    }
    setState(() => _loading = true);
    final email = _email.text.trim();
    try {
      final res = await supabase.auth.signUp(
        email: email,
        password: _password.text,
        // Estos datos los lee el trigger SQL para crear el perfil
        data: {
          'first_name': _firstName.text.trim(),
          'last_name': _lastName.text.trim(),
          'phone': _phone.text.trim(),
          'country': _country.text.trim(),
          'city': _city.text.trim(),
          'consent': true,
        },
      );
      if (!mounted) return;
      // Supabase no da error si el correo ya existe: devuelve identities vacío
      if (res.user?.identities?.isEmpty ?? false) {
        showMessage(context, 'Este correo ya está registrado. Inicia sesión.',
            error: true);
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VerifyOtpPage(email: email)),
      );
    } on AuthException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } catch (_) {
      if (mounted) {
        showMessage(context, 'Error de conexión. Intenta de nuevo.',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? Function(String?)? validator,
    TextInputType? type,
    bool password = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: type,
        obscureText: password ? _obscure : false,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: password
              ? IconButton(
                  icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                )
              : null,
        ),
        validator: validator,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _field(_firstName, 'Nombres', validator: _required),
                _field(_lastName, 'Apellidos', validator: _required),
                _field(_email, 'Correo electrónico',
                    validator: _validateEmail, type: TextInputType.emailAddress),
                _field(_phone, 'Teléfono (opcional)', type: TextInputType.phone),
                _field(_country, 'País', validator: _required),
                _field(_city, 'Ciudad', validator: _required),
                _field(_password, 'Contraseña',
                    validator: _validatePassword, password: true),
                _field(_confirm, 'Confirmar contraseña',
                    validator: _validateConfirm, password: true),
                CheckboxListTile(
                  value: _consent,
                  onChanged: (v) => setState(() => _consent = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Acepto el tratamiento de mis datos personales y de '
                    'ubicación para el uso de la aplicación.',
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _loading ? null : _register,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Registrarme'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}