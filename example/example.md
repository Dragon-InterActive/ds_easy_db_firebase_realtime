# DSEasyDB Firebase Realtime Example

```dart
import 'package:ds_easy_db/ds_easy_db.dart';
import 'package:ds_easy_db_firebase_realtime/ds_easy_db_firebase_realtime.dart';
import 'firebase_options.dart';

void main() async {
  // Configure with Firebase Realtime Database
  db.configure(
    prefs: MockDatabase(),
    secure: MockDatabase(),
    storage: MockDatabase(),
    stream: FirebaseRealtimeDatabase(
      options: DefaultFirebaseOptions.currentPlatform,
    ),
  );
  
  await db.init();
  
  // Watch single user for real-time updates
  db.stream.watch('users', 'user123').listen((userData) {
    if (userData != null) {
      print('User updated: ${userData['name']}');
    }
  });
  
  // Set user data
  await db.stream.set('users', 'user123', {
    'name': 'John Doe',
    'online': true,
    'lastSeen': DatabaseRepository.serverTS,
  });
  
  // Watch online users
  db.stream.watchQuery('users',
    where: {'online': true}
  ).listen((onlineUsers) {
    print('Online users: ${onlineUsers.length}');
  });
  
  // Update user status
  await db.stream.update('users', 'user123', {
    'online': false,
    'lastSeen': DatabaseRepository.serverTS,
  });
}
```
