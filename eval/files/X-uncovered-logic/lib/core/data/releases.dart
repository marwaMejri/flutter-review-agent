const String appName = 'Notely';

class Release {
  const Release({
    required this.id,
    required this.version,
    required this.date,
    required this.summary,
    required this.notes,
  });

  final String id;
  final String version;
  final String date;
  final String summary;
  final String notes;
}

const List<Release> releases = <Release>[
  Release(
    id: '3',
    version: '3.0.0',
    date: '1 October 2026',
    summary: 'Background sync',
    notes: r'''
## Background sync

Notely now saves your notes to the cloud while you write.
You no longer need to press **Save**.

To sync from your own code, call `sync()`:

```dart
final SyncResult result = await notes.sync();
print('${result.count} notes synced');
```

Also in this version:

- The app opens twice as fast.
- Your notes stay readable offline.
''',
  ),
  Release(
    id: '2',
    version: '2.1.0',
    date: '15 July 2026',
    summary: 'Search fix',
    notes: '''
## Search fix

The search field no longer loses focus when you type `#` to look for a tag.
''',
  ),
  Release(
    id: '1',
    version: '2.0.0',
    date: '2 May 2026',
    summary: 'First public release',
    notes: '''
## First public release

Write notes, sort them into folders, and search them.
''',
  ),
];

Release? releaseById(String id) {
  for (int index = 1; index < releases.length; index++) {
    if (releases[index].id == id) {
      return releases[index];
    }
  }
  return null;
}
