import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'firebase_options.dart';

// --- Core Screens ---
import 'screens/login_page.dart';
import 'screens/dashboard_page.dart';
import 'screens/attendance_dashboard.dart';
import 'screens/attendance_history.dart';
import 'screens/fees_dashboard.dart';
import 'screens/fee_ledger.dart';
import 'screens/fee_invoice_details.dart';
import 'screens/memory_journey/memory_dashboard.dart';
import 'screens/memory_journey/monthly_story_page.dart';

// --- Teacher Module ---
import 'screens/teacher/teacher_profile_page.dart';
import 'screens/teacher/teacher_model.dart';

// --- QR & Parent Profile ---
import 'screens/pickup_scanner.dart';

/// =======================================================
/// 🔔 Notification Setup
/// =======================================================

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Handle background messages (app closed / minimized)
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print('📩 Background Message: ${message.notification?.title}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    print('🚀 Initializing Firebase...');
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    print('✅ Firebase initialized successfully');

    // 🔔 FCM background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 🔔 Local notification setup
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidInit);

    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Bila tekan noti → buka attendance dashboard
        navigatorKey.currentState?.pushNamed('/attendance_dashboard');
      },
    );

    // 🔔 Request notification permission
    final fcm = FirebaseMessaging.instance;
    NotificationSettings settings = await fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    print('🔔 Permission status: ${settings.authorizationStatus}');

    // 🔔 Dapatkan dan print FCM token
    String? token = await fcm.getToken();
    print('📱 Parent FCM Token: $token');

    // 🔔 Listen to foreground messages (masa app tengah buka)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      print('📨 Foreground message: ${message.notification?.title}');
      await _showLocalNotification(message);
    });

  } catch (e) {
    print('🔥 Error initializing Firebase: $e');
  }

  runApp(const MyApp());
}

// 🔔 Function untuk paparkan notification masa foreground
Future<void> _showLocalNotification(RemoteMessage message) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'taska_zurah_channel',
    'Taska Zurah Notifications',
    importance: Importance.max,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );
  const NotificationDetails platformDetails =
      NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.show(
    0,
    message.notification?.title ?? 'Attendance Update',
    message.notification?.body ?? 'Your child has checked in/out.',
    platformDetails,
    payload: '/attendance_dashboard',
  );
}

/// =======================================================
/// 🌿 App Entry
/// =======================================================
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Taska Zurah',
      theme: ThemeData(
        primarySwatch: Colors.green,
        fontFamily: 'Poppins',
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginPage(),
        '/dashboard': (context) => const TaskaZurahDashboard(),
        '/fees_dashboard': (context) => const FeesPaymentPage(),
        '/fee_ledger': (context) => const MonthlyLedgerPage(),
        '/fee_invoice_details': (context) => const InvoiceDetailsPage(),
        '/memory_journey': (context) => const MemoryJourneyPage(),
        '/monthly_story': (context) => const MonthlyStoryPage(),
        '/teacher_list': (context) => const TeacherListPage(),
        '/teacher_profile': (context) => const TeacherProfilePage(
              teacher: Teacher(
                id: 'temp',
                name: 'Example Teacher',
                imageUrl: '',
                className: '',
                experience: '',
              ),
            ),
        '/pickup_scanner': (context) => const PickupScannerPage(),
      },
      onGenerateRoute: (settings) {
        final args = settings.arguments as Map<String, dynamic>?;

        switch (settings.name) {
          case '/attendance_dashboard':
            if (args != null) {
              return MaterialPageRoute(
                builder: (context) => AttendancePage(
                  childId: args['childId'] as String,
                  childName: args['childName'] as String,
                  className: args['className'] as String,
                ),
              );
            } else {
              // Fallback ke default child (kalau datang dari notification tanpa argumen)
              return MaterialPageRoute(
                builder: (context) => const AttendancePage(
                  childId: 'default_child',
                  childName: 'Unknown',
                  className: 'Class',
                ),
              );
            }

          case '/attendance_history':
            if (args != null) {
              return MaterialPageRoute(
                builder: (context) => AttendanceHistoryPage(
                  childId: args['childId'] as String,
                  childName: args['childName'] as String,
                  className: args['className'] as String,
                ),
              );
            }
            break;
        }

        // Fallback (404)
        return MaterialPageRoute(
          builder: (context) => const Scaffold(
            body: Center(
              child: Text(
                '404 - Page not found',
                style: TextStyle(fontSize: 18, color: Colors.redAccent),
              ),
            ),
          ),
        );
      },
    );
  }
}
