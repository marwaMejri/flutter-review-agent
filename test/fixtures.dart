/// A diff with one changed file and one deleted file.
const String sampleDiff = '''
diff --git a/lib/a.dart b/lib/a.dart
index 1111111..2222222 100644
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -10,4 +10,5 @@ class A {
   final int x;
-  final int y;
+  final int z;
+  final int w;
   void run() {}
diff --git a/lib/old.dart b/lib/old.dart
deleted file mode 100644
--- a/lib/old.dart
+++ /dev/null
@@ -1,2 +0,0 @@
-void old() {}
-
''';
