import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:material_ui_packages_migration/features/changelog/changelog_page.dart';
import 'package:material_ui_packages_migration/features/release_detail/release_detail_page.dart';
import 'package:material_ui_packages_migration/features/releases/releases_page.dart';
import 'package:material_ui_packages_migration/features/settings/settings_page.dart';

GoRouter createRouter() {
  return GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            const ReleasesPage(),
        routes: <RouteBase>[
          GoRoute(
            path: 'releases/:id',
            builder: (BuildContext context, GoRouterState state) =>
                ReleaseDetailPage(id: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'changelog',
            builder: (BuildContext context, GoRouterState state) =>
                const ChangelogPage(),
          ),
          GoRoute(
            path: 'settings',
            builder: (BuildContext context, GoRouterState state) =>
                const SettingsPage(),
          ),
        ],
      ),
    ],
  );
}
