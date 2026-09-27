import 'package:flutter/material.dart';

import '../widgets/hermes_sessions_tab.dart';
import 'hermes_page_chrome.dart';

class HermesConversationsPage extends StatelessWidget {
  const HermesConversationsPage({super.key});

  @override
  Widget build(BuildContext context) => const HermesPageChrome(
    title: 'Conversations',
    subtitle: 'Every chat, organized by bot.',
    child: HermesSessionsTab(showBottomNavigationBar: false, standalone: true),
  );
}
