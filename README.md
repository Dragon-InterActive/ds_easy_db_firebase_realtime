# EasyDB Firebase Realtime

Firebase Realtime Database implementation for [DS-EasyDB](https://pub.dev/packages/ds_easy_db) (<https://github.com/Dragon-InterActive/ds_easy_db>). Provides real-time data synchronization with streaming support for Flutter applications.

## Features

- **Real-Time Synchronization**: Instant data updates across all connected clients
- **Streaming Support**: Built-in reactive streams for live data
- **Offline Support**: Automatic data caching and synchronization when back online
- **Low Latency**: Optimized for speed with minimal delay
- **JSON-Based**: Simple JSON structure for easy data modeling
- **Cross-Platform**: Works on iOS, Android, Web, macOS, Windows

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  ds_easy_db: ^1.0.1
  ds_easy_db_firebase_realtime: ^1.0.1
  firebase_core: ^4.2.1  # Required for Firebase initialization
```

## Firebase Setup

### 1. Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project or select existing one
3. Enable Realtime Database in the "Build" section
4. Choose a database location (closest to your users)
5. Start in test mode (configure security rules later)

### 2. Install Firebase CLI

```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
```

### 3. Configure Firebase

```bash
# Login to Firebase
firebase login

# Configure FlutterFire
flutterfire configure
```

This creates `firebase_options.dart` with your Firebase configuration.

## Usage

### Basic Setup

In your `ds_easy_db_config.dart`:

```dart
import 'package:ds_easy_db/ds_easy_db.dart';
import 'package:ds_easy_db_firebase_realtime/ds_easy_db_firebase_realtime.dart';
import 'firebase_options.dart'; // Your generated Firebase config

class EasyDBConfig {
  static DatabaseStreamRepository get stream => FirebaseRealtimeDatabase(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // ... other configurations
}
```

In your `main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:ds_easy_db/ds_easy_db.dart';
import 'ds_easy_db_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configure EasyDB
  db.configure(
    stream: EasyDBConfig.stream,
    // ... other configurations
  );
  
  // Firebase is automatically initialized when db.init() is called
  await db.init();
  
  runApp(MyApp());
}
```

## Examples

### Watch Single Document

```dart
// Listen to user changes in real-time
db.stream.watch('users', 'user123').listen((userData) {
  if (userData != null) {
    print('User updated: ${userData['name']}');
  } else {
    print('User deleted');
  }
});
```

### Watch Entire Collection

```dart
// Listen to all users
db.stream.watchAll('users').listen((allUsers) {
  if (allUsers != null) {
    print('Total users: ${allUsers.length}');
  }
});
```

### Watch with Query

```dart
// Watch only online users
db.stream.watchQuery('users', 
  where: {'online': true}
).listen((onlineUsers) {
  print('Online users: ${onlineUsers.length}');
  for (var user in onlineUsers) {
    print('- ${user['name']} is online');
  }
});
```

### Write Data

```dart
// Create or update user
await db.stream.set('users', 'user123', {
  'name': 'John Doe',
  'online': true,
  'lastSeen': DatabaseRepository.serverTS, // Uses ServerValue.timestamp
});

// Update specific fields
await db.stream.update('users', 'user123', {
  'online': false,
  'lastSeen': DatabaseRepository.serverTS,
});

// Delete user
await db.stream.delete('users', 'user123');
```

### Real-Time Chat Example

```dart
class ChatScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: db.stream.watchQuery('messages',
        where: {'roomId': 'room123'}
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return CircularProgressIndicator();
        }

        final messages = snapshot.data!;
        return ListView.builder(
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            return ListTile(
              title: Text(message['text']),
              subtitle: Text(message['sender']),
            );
          },
        );
      },
    );
  }
}

// Send message
Future<void> sendMessage(String text) async {
  await db.stream.set('messages', DateTime.now().millisecondsSinceEpoch.toString(), {
    'text': text,
    'sender': 'user123',
    'roomId': 'room123',
    'timestamp': DatabaseRepository.serverTS,
  });
}
```

### Presence System

```dart
// Set user online
await db.stream.set('presence', userId, {
  'online': true,
  'lastSeen': DatabaseRepository.serverTS,
});

// Watch user presence
db.stream.watch('presence', userId).listen((presence) {
  if (presence?['online'] == true) {
    print('User is online');
  } else {
    print('User was last seen at: ${presence?['lastSeen']}');
  }
});

// Set offline on disconnect (use Firebase SDK directly)
FirebaseDatabase.instance
  .ref('presence/$userId')
  .onDisconnect()
  .update({'online': false, 'lastSeen': ServerValue.timestamp});
```

### Live Counter

```dart
class LiveCounterWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: db.stream.watch('counters', 'visitors'),
      builder: (context, snapshot) {
        final count = snapshot.data?['count'] ?? 0;
        
        return Column(
          children: [
            Text('Visitors: $count'),
            ElevatedButton(
              onPressed: () async {
                await db.stream.update('counters', 'visitors', {
                  'count': count + 1,
                });
              },
              child: Text('Increment'),
            ),
          ],
        );
      },
    );
  }
}
```

### Live Location Tracking

```dart
// Update location
await db.stream.update('locations', userId, {
  'lat': 52.5200,
  'lng': 13.4050,
  'timestamp': DatabaseRepository.serverTS,
});

// Watch all locations
db.stream.watchAll('locations').listen((locations) {
  if (locations != null) {
    locations.forEach((userId, location) {
      print('$userId is at: ${location['lat']}, ${location['lng']}');
    });
  }
});
```

## Security Rules

Configure Firebase Realtime Database security rules in Firebase Console:

```json
{
  "rules": {
    "users": {
      "$uid": {
        ".read": "auth != null",
        ".write": "auth != null && auth.uid == $uid"
      }
    },
    "messages": {
      ".read": "auth != null",
      ".write": "auth != null"
    },
    "presence": {
      "$uid": {
        ".read": true,
        ".write": "auth != null && auth.uid == $uid"
      }
    }
  }
}
```

## Data Structure Best Practices

### ✅ Good Structure (Flat & Denormalized)

```dart
// Users
await db.stream.set('users', 'user123', {
  'name': 'John',
  'email': 'john@example.com',
});

// User posts (separate collection)
await db.stream.set('posts/user123', 'post1', {
  'title': 'Hello World',
  'content': 'My first post',
});
```

### ❌ Bad Structure (Deeply Nested)

```dart
// Don't do this!
await db.stream.set('users', 'user123', {
  'name': 'John',
  'posts': {
    'post1': {
      'title': 'Hello',
      'comments': {
        'comment1': {...}  // Too deep!
      }
    }
  }
});
```

## Offline Support

Realtime Database automatically caches data:

```dart
// Enable offline persistence (enabled by default)
FirebaseDatabase.instance.setPersistenceEnabled(true);

// Data is automatically synced when connection is restored
await db.stream.set('users', 'user123', {
  'name': 'John',
  'lastUpdated': DatabaseRepository.serverTS,
});
```

## Performance Tips

1. **Keep Data Flat**: Avoid deep nesting (max 32 levels)
2. **Denormalize Data**: Duplicate data for faster reads
3. **Use Indexing**: Define indexes in Firebase Console for queries
4. **Limit Listeners**: Don't watch entire large collections
5. **Use Priority**: Set priorities for sorting without reading all data

## Realtime vs Firestore

| Feature | Realtime Database | Firestore |
|---------|------------------|-----------|
| Data Model | JSON tree | Document collections |
| Latency | Lower | Slightly higher |
| Queries | Limited | More powerful |
| Offline | Automatic | Automatic |
| Pricing | Per GB | Per operation |
| Best For | Real-time apps | Complex queries |

## When to Use

### ✅ Perfect for Realtime Database

- Chat applications
- Live tracking (location, status)
- Collaborative editing
- Real-time gaming
- Presence systems
- Live counters/metrics
- Social feeds

### ❌ Consider Firestore Instead

- Complex queries
- Large datasets
- Document-based data
- Advanced filtering
- Transactions

## Limitations

- **Data Size**: 1GB free tier
- **Connections**: 100 simultaneous free tier
- **Depth**: Maximum 32 levels of nesting
- **Query**: Limited to single orderBy per query
- **Write Size**: Maximum 256MB per write

## Pricing

Firebase Realtime Database offers a generous free tier:

- **Storage**: 1GB
- **Downloads**: 10GB/month
- **Connections**: 100 simultaneous

See [Firebase Pricing](https://firebase.google.com/pricing) for details.

## Troubleshooting

### Permission Denied

```
// Error: PERMISSION_DENIED
// Solution: Update security rules in Firebase Console
```

### Data Not Syncing

```dart
// Check connection status
FirebaseDatabase.instance.ref('.info/connected').onValue.listen((event) {
  if (event.snapshot.value == true) {
    print('Connected to Firebase');
  } else {
    print('Disconnected from Firebase');
  }
});
```

### Slow Queries

```dart
// Use indexing - define in Firebase Console:
// {
//   "rules": {
//     "users": {
//       ".indexOn": ["name", "age"]
//     }
//   }
// }
```

## License

BSD-3-Clause License - see LICENSE file for details.

Copyright (c) 2025, MasterNemo (Dragon Software)

---

Feel free to clone and extend. It's free to use and share.
