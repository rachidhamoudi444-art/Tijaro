import 'package:flutter/material.dart' hide Text;
import 'core/i18n.dart';

import 'core/api.dart';
import 'core/phone.dart';
import 'core/brand.dart';
import 'core/app_mode.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = normalizePhone(_phone.text);
    final pass = _password.text;
    if (_register && !isValidMobile(phone)) {
      setState(() => _error = 'أدخل رقم هاتف جزائري صحيح (موبيليس 06 / أوريدو 05 / جازي 07)، مثال: 0550123456');
      return;
    }
    if (phone.length < 9 || pass.length < 6) {
      setState(() => _error = 'أدخل رقم الهاتف وكلمة مرور من 6 أحرف على الأقل');
      return;
    }
    if (_register && _name.text.trim().length < 2) {
      setState(() => _error = 'أدخل اسمك');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await db.auth.signUp(
          email: phoneToEmail(phone),
          password: pass,
          data: {'phone': phone, 'full_name': _name.text.trim()},
        );
      } else {
        await db.auth.signInWithPassword(email: phoneToEmail(phone), password: pass);
      }
      // AuthGate يتولى الانتقال تلقائياً
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(alignment: AlignmentDirectional.centerEnd, child: LangToggle()),
                  const SizedBox(height: 8),
                  const TijaroLogo(),
                  const SizedBox(height: 6),
                  if (!isCustomerApp)
                    Text(appModeName,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold))
                  else
                    Text('كل التجارة في بلاصة وحدة',
                        textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 32),
                  if (_register) ...[
                    TextField(
                      controller: _name,
                      decoration: InputDecoration(labelText: tr('الاسم')),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(labelText: tr('رقم الهاتف'), hintText: '05XX XX XX XX'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: InputDecoration(labelText: tr('كلمة المرور')),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _busy
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_register ? 'إنشاء حساب زبون' : 'دخول'),
                    ),
                  ),
                  if (isCustomerApp)
                    TextButton(
                      onPressed: _busy ? null : () => setState(() => _register = !_register),
                      child: Text(_register ? 'لدي حساب' : 'حساب جديد (زبون)'),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('لفتح حساب، تواصل مع إدارة Tijaro',
                          textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
