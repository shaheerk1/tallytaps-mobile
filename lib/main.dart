import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/action_repository.dart';
import 'screens/home_screen.dart';
import 'state/tally_store.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = TallyStore(ActionRepository());
  await store.refresh();
  runApp(
    ChangeNotifierProvider.value(
      value: store,
      child: const TallyApp(),
    ),
  );
}

class TallyApp extends StatelessWidget {
  const TallyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TallyTaps',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const HomeScreen(),
    );
  }
}
