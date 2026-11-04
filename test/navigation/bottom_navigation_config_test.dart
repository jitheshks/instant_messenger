// test/navigation/bottom_navigation_config_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:instant_messenger/app/navigation/navigation_config.dart';
import 'package:instant_messenger/app/navigation/tab_controller_model.dart';
import 'package:instant_messenger/features/chats/presentation/screens/updates_tab.dart';

void main() {
  group('Bottom Navigation Configuration Tests', () {
    test('1. Exactly three tabs are visible: Chats, Communities, and Calls', () {
      final visibleItems = BottomNavigationConfig.visibleItems;
      expect(visibleItems.length, equals(3));
      expect(visibleItems[0], equals(NavigationTabItem.chats));
      expect(visibleItems[1], equals(NavigationTabItem.communities));
      expect(visibleItems[2], equals(NavigationTabItem.calls));

      final visiblePaths = BottomNavigationConfig.visiblePaths;
      expect(visiblePaths, equals(['/chats', '/communities', '/calls']));
    });

    test('2. TabControllerModel delegates tabs list to BottomNavigationConfig.visiblePaths', () {
      expect(TabControllerModel.tabs, equals(['/chats', '/communities', '/calls']));
    });

    test('3. Maps route locations to correct visible tab indices', () {
      expect(BottomNavigationConfig.indexForLocation('/chats'), equals(0));
      expect(BottomNavigationConfig.indexForLocation('/chats/chat/123'), equals(0));

      expect(BottomNavigationConfig.indexForLocation('/communities'), equals(1));
      expect(BottomNavigationConfig.indexForLocation('/communities/group/abc'), equals(1));

      expect(BottomNavigationConfig.indexForLocation('/calls'), equals(2));
      expect(BottomNavigationConfig.indexForLocation('/calls/history'), equals(2));
    });

    test('4. Updates tab feature implementation is completely preserved', () {
      // Configuration flag exists and documents temporary visibility toggle
      expect(BottomNavigationConfig.isUpdatesTabVisible, isFalse);

      // NavigationTabItem.updates exists in enum definition
      expect(NavigationTabItem.values.contains(NavigationTabItem.updates), isTrue);
      expect(NavigationTabItem.updates.path, equals('/updates'));
      expect(NavigationTabItem.updates.label, equals('Updates'));

      // Screen builder creates UpdatesTab without error
      final screen = NavigationTabItem.updates.buildScreen();
      expect(screen, isA<UpdatesTab>());

      // Route check recognizes /updates as a known tab route for shell preservation
      expect(BottomNavigationConfig.isTabRoute('/updates'), isTrue);
      expect(BottomNavigationConfig.isVisibleTabRoute('/updates'), isFalse);
    });

    test('5. Direct navigation to hidden updates route falls back safely without index out of bounds', () {
      final index = BottomNavigationConfig.indexForLocation('/updates');
      // Defaults to 0 (Chats) for visible tab indexing safely
      expect(index, equals(0));
      expect(index, lessThan(BottomNavigationConfig.visibleItems.length));
    });
  });
}
