import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/api.dart';
import 'courier/courier_home.dart';
import 'customer/customer_home.dart';
import 'login_screen.dart';

/// يوجّه المستخدم حسب حالة الدخول ودوره.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: db.auth.onAuthStateChange,
      builder: (context, _) {
        final session = db.auth.currentSession;
        if (session == null) return const LoginScreen();
        return const _RoleRouter();
      },
    );
  }
}

class _RoleRouter extends StatelessWidget {
  const _RoleRouter();

  Future<Map<String, dynamic>> _profile() async {
    final uid = db.auth.currentUser!.id;
    return await db.from('profiles').select().eq('id', uid).single();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _profile(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(friendlyError(snap.error!)),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => db.auth.signOut(), child: const Text('خروج')),
              ]),
            ),
          );
        }
        final p = snap.data!;
        if (p['state'] != 'active') {
          return _Notice(
            text: 'حسابك غير نشط (${p['state']}). تواصل مع الإدارة.',
          );
        }
        switch (p['role']) {
          case 'courier':
            return const CourierHome();
          case 'customer':
            return const CustomerHome();
          case 'store':
          case 'admin':
            return const _Notice(text: 'المتجر والأدمن يستعملان لوحة الويب (قيد البناء).');
          default:
            return const _Notice(text: 'دور غير معروف');
        }
      },
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  const _Notice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: () => db.auth.signOut(), child: const Text('تسجيل الخروج')),
          ]),
        ),
      ),
    );
  }
}
