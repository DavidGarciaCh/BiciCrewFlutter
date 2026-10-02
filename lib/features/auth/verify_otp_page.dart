import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_config.dart';
import '../../core/utils.dart';

class VerifyOtpPage extends StatefulWidget {
  final String email;
  const VerifyOtpPage({super.key, required this.email});

  @override
  State<VerifyOtpPage> createState() => _VerifyOtpPageState();
}

class _VerifyOtpPageState extends State<VerifyOtpPage> {
  final _code = TextEditingController();
  bool _loading = false;
  int _cooldown = 60; // Supabase limita los reenvíos a 1 por minuto
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _cooldown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_cooldown <= 1) {
        t.cancel();
      }
      if (mounted) setState(() => _cooldown--);
    });
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length < 6) {
      showMessage(context, 'Ingresa el código completo', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await supabase.auth.verifyOTP(
        type: OtpType.signup,
        email: widget.email,
        token: code,
      );
      if (!mounted) return;
      // Sesión iniciada: cerramos estas pantallas y AuthGate muestra Home.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException {
      if (mounted) {
        showMessage(context, 'Código incorrecto o vencido', error: true);
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

  Future<void> _resend() async {
    try {
      await supabase.auth.resend(type: OtpType.signup, email: widget.email);
      if (!mounted) return;
      showMessage(context, 'Código reenviado');
      _startCooldown();
    } on AuthException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verificar correo')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                'Enviamos un código a\n${widget.email}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text('Revisa también la carpeta de spam.'),
              const SizedBox(height: 24),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 28, letterSpacing: 6),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  counterText: '',
                  hintText: 'Código',
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _verify,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verificar'),
                ),
              ),
              TextButton(
                onPressed: _cooldown > 0 ? null : _resend,
                child: Text(_cooldown > 0
                    ? 'Reenviar código en ${_cooldown}s'
                    : 'Reenviar código'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}