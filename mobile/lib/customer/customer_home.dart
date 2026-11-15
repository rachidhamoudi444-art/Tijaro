import 'package:flutter/material.dart' hide Text;
import '../core/i18n.dart';

import 'account_tab.dart';
import 'free_order_tab.dart';
import 'home_tab.dart';
import 'orders_tab.dart';
import 'store_screen.dart';
import 'stores_tab.dart';

/// الهيكل الرئيسي للزبون: أربع تبويبات (الرئيسية، المتاجر، ليفرور، حسابي).
class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});

  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  int _tab = 0;
  String? _group;
  String _query = '';
  int _storesKey = 0;
  int _freeKey = 0;

  static const _titles = ['', 'المتاجر', 'اطلب ليفرور', 'حسابي'];

  void _openStores(String? group, String query) {
    setState(() {
      _tab = 1;
      _group = group;
      _query = query;
      _storesKey++;
    });
  }

  Future<void> _openStore(Map<String, dynamic> store) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => StoreScreen(store: store)),
    );
    if (created == true && mounted) _openOrders();
  }

  void _openOrders() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeTab(
        onOpenStores: _openStores,
        onOpenCourier: () => setState(() => _tab = 2),
        onOpenStore: _openStore,
      ),
      StoresTab(
        key: ValueKey('stores$_storesKey'),
        initialGroup: _group,
        initialQuery: _query,
        onOpenStore: _openStore,
      ),
      FreeOrderTab(
        key: ValueKey('free$_freeKey'),
        onCreated: () {
          setState(() {
            _freeKey++;
            _tab = 0;
          });
          _openOrders();
        },
      ),
      AccountTab(onOpenOrders: _openOrders),
    ];
    return Scaffold(
      appBar: _tab == 0 ? null : AppBar(title: Text(_titles[_tab])),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: tr('الرئيسية')),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: tr('المتاجر')),
          NavigationDestination(icon: Icon(Icons.delivery_dining_outlined), selectedIcon: Icon(Icons.delivery_dining), label: tr('ليفرور')),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: tr('حسابي')),
        ],
      ),
    );
  }
}
