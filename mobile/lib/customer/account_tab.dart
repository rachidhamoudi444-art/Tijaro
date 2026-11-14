import 'package:flutter/material.dart';

import '../core/api.dart';

class AccountTab extends StatelessWidget {
  final VoidCallback onOpenOrders;
  const AccountTab({super.key, required this.onOpenOrders});

  Future<Map<String, dynamic>> _profile() async {
    return await db.from('profiles').select('full_name,phone').eq('id', db.auth.currentUser!.id).single();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _profile(),
      builder: (context, snap) {
        final p = snap.data;
        final name = (p?['full_name'] as String?)?.trim();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              const CircleAvatar(radius: 28, child: Icon(Icons.person, size: 30)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text((name == null || name.isEmpty) ? 'زبون' : name,
                      style: Theme.of(context).textTheme.titleLarge),
                  if (p?['phone'] != null)
                    Text('${p!['phone']}', textDirection: TextDirection.ltr),
                ]),
              ),
            ]),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('طلباتي'),
                trailing: const Icon(Icons.chevron_left),
                onTap: onOpenOrders,
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('تسجيل الخروج'),
                onTap: () => db.auth.signOut(),
              ),
            ),
          ],
        );
      },
    );
  }
}
