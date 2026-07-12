import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/settings_notifier.dart';

class OnboardingScreen extends StatelessWidget {
  final bool showGetStarted;

  const OnboardingScreen({super.key, this.showGetStarted = true});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to Gazoo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gazoo makes a remote Minecraft: Bedrock Edition server appear as a '
              'LAN game to your console. Your console and this device must be on '
              'the same Wi-Fi/local network for this to work.',
            ),
            const SizedBox(height: 16),
            Text(_platformNote(), style: Theme.of(context).textTheme.bodyMedium),
            const Spacer(),
            if (showGetStarted)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('get-started-button'),
                  onPressed: () async {
                    await context.read<SettingsNotifier>().update(
                          (s) => s.copyWith(hasSeenOnboarding: true),
                        );
                  },
                  child: const Text('Get Started'),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Close'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _platformNote() {
    if (Platform.isAndroid) {
      return 'Android: Gazoo needs Wi-Fi and multicast permissions, and runs '
          'the relay as a foreground service with a persistent notification '
          'while active.';
    }
    if (Platform.isIOS) {
      return 'iOS: you\'ll be asked to allow Gazoo to find and connect to '
          'devices on your local network. iOS suspends background apps, so '
          'keep Gazoo open while playing.';
    }
    return 'Desktop: you may need to allow Gazoo through your firewall for '
        'incoming UDP connections on port 19132 (Windows Defender Firewall, '
        'macOS\'s incoming-connection prompt, or ufw/firewalld on Linux).';
  }
}
