import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_config.dart';
import '../../core/utils.dart';

class ResetPasswordPage extends StatefulWidget {
  final String email;
  const ResetPasswordPage({super.key, required this.email});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    if (_code.text.trim().length < 6) {
      showMessage(context, 'Ingresa el código completo', error: true);
      return;
    }
    if (_password.text.length < 8) {
      showMessage(context, 'La contraseña debe tener mínimo 8 caracteres',
          error: true);
      return;
    }
    if (_password.text != _confirm.text) {
      showMessage(context, 'Las contraseñas no coinciden', error: true);
      return;
    }
    setState(() => _loading = true);
    bool verified = false;
    try {
      // Paso 1: validar el código (esto inicia sesión temporalmente)
      await supabase.auth.verifyOTP(
        type: OtpType.recovery,
        email: widget.email,
        token: _code.text.trim(),
      );
      verified = true;
      // Paso 2: cambiar la contraseña
      await supabase.auth.updateUser(UserAttributes(password: _password.text));
      if (!mounted) return;
      showMessage(context, 'Contraseña actualizada');
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      if (mounted) {
        showMessage(
          context,
          verified ? e.message : 'Código incorrecto o vencido',
          error: true,
        );
      }
    } catch (_) {
      if (mounted) {
        showMessage(context, 'Error de conexión. Intenta de nuevo.',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva contraseña')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text('Enviamos un código a\n${widget.email}',
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Código',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Nueva contraseña',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                obscureText: _obscure,
                decoration: const InputDecoration(
                  labelText: 'Confirmar contraseña',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _reset,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Cambiar contraseña'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}