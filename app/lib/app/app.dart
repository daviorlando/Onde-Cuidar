import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/search/presentation/home_page.dart';
import 'theme.dart';

class OndeCuidarApp extends StatelessWidget {
  const OndeCuidarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Onde Cuidar',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const HomePage(),
    );
  }
}
