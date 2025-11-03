import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:table_calendar/table_calendar.dart';

void main() {
  runApp(BirthdayApp());
}

class BirthdayApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Time to Wish',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
        useMaterial3: true,
      ),
      home: BirthdayHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class BirthdayHomePage extends StatefulWidget {
  @override
  _BirthdayHomePageState createState() => _BirthdayHomePageState();
}

class _BirthdayHomePageState extends State<BirthdayHomePage> {
  int _selectedIndex = 0;
  final TextEditingController _nameController = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  List<Map<String, dynamic>> _birthdays = [];
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  Map<String, String> _todaysVerse = {'reference': '', 'text': 'Loading...'};

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    tz.setLocalLocation(
      tz.getLocation('Asia/Kolkata'),
    ); // or your local timezone
    final initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    flutterLocalNotificationsPlugin.initialize(initializationSettings);
    _requestNotificationPermission(); // <-- Add this line
    _loadBirthdaysFromFile();
    fetchTodaysVerse().then((verse) {
      setState(() {
        _todaysVerse = verse;
      });
    });
  }

  Future<void> _requestNotificationPermission() async {
    if (Platform.isAndroid) {
      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      final androidImplementation = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
    }
  }

  void _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _pickTime() async {
    TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<void> _scheduleBirthdayNotification(
    String name,
    DateTime date,
    TimeOfDay time,
  ) async {
    final now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(Duration(days: 365));
    }

    print(
      'Scheduling notification for $scheduledDate, now is ${tz.TZDateTime.now(tz.local)}',
    );

    try {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        date.hashCode + time.hour + time.minute,
        'Event Reminder',
        "It's $name's! Wish them fast!!",
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails('event_channel', 'Events'),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
        // Remove uiLocalNotificationDateInterpretation for web/desktop
      );
    } catch (e) {
      print('Notification scheduling error: $e');
    }
  }

  void _addBirthday() async {
    if (_nameController.text.isEmpty ||
        _selectedDate == null ||
        _selectedTime == null)
      return;

    setState(() {
      _birthdays.add({
        'name': _nameController.text.trim(),
        'date': _selectedDate!,
        'time': _selectedTime!,
      });
      _nameController.clear();
      _selectedDate = null;
      _selectedTime = null;
    });

    await _saveBirthdaysToFile();
    await _scheduleBirthdayNotification(
      _birthdays.last['name'],
      _birthdays.last['date'],
      _birthdays.last['time'],
    );
  }

  void _deleteBirthday(int index) async {
    setState(() {
      _birthdays.removeAt(index);
    });
    await _saveBirthdaysToFile();
  }

  Future<Directory> _getAppDirectory() async {
    final Directory baseDir = await getApplicationDocumentsDirectory();
    final Directory appDir = Directory('${baseDir.path}/timetowish');
    if (!(await appDir.exists())) {
      await appDir.create(recursive: true);
    }
    return appDir;
  }

  Future<void> _saveBirthdaysToFile() async {
    final Directory appDir = await _getAppDirectory();
    final File file = File('${appDir.path}/birthdays.json');
    List<Map<String, dynamic>> toSave = _birthdays
        .map(
          (b) => {
            'name': b['name'],
            'date': b['date'].toIso8601String(),
            'time': {'hour': b['time'].hour, 'minute': b['time'].minute},
          },
        )
        .toList();
    await file.writeAsString(jsonEncode(toSave));
  }

  Future<void> _loadBirthdaysFromFile() async {
    try {
      final Directory appDir = await _getAppDirectory();
      final File file = File('${appDir.path}/birthdays.json');
      if (await file.exists()) {
        String contents = await file.readAsString();
        List<dynamic> decoded = jsonDecode(contents);
        setState(() {
          _birthdays = decoded
              .map(
                (b) => {
                  'name': b['name'],
                  'date': DateTime.parse(b['date']),
                  'time': TimeOfDay(
                    hour: b['time']['hour'],
                    minute: b['time']['minute'],
                  ),
                },
              )
              .toList();
        });
      }
    } catch (e) {
      // Handle error or show message
    }
  }

  Future<Map<String, String>> fetchTodaysVerse() async {
    try {
      final response = await http.get(
        Uri.parse('https://beta.ourmanna.com/api/v1/get/?format=json'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final verse = data['verse']['details'];
        return {
          'reference': verse['reference'] ?? '',
          'text': verse['text'] ?? 'No verse found',
        };
      } else {
        return {'reference': '', 'text': 'Unable to fetch verse'};
      }
    } catch (e) {
      return {'reference': '', 'text': 'Unable to fetch verse'};
    }
  }

  List<Widget> get _pages => [
    _buildHomePage(),
    _buildRemainderPage(),
    _buildCalendarPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFbbc5cf),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.black54,
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.alarm), label: 'Reminder'),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Calendar',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.black,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () async {
          await flutterLocalNotificationsPlugin.show(
            0,
            'Test Notification',
            'This is a test notification from Time to Wish!',
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'event_channel',
                'Events',
                importance: Importance.max,
                priority: Priority.high,
              ),
              iOS: DarwinNotificationDetails(),
            ),
          );
        },
        tooltip: 'Send Test Notification',
      ),
    );
  }

  Widget _buildHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Container(height: 2, width: 60, color: Color(0xFFbbc5cf)),
        ],
      ),
    );
  }

  Widget _buildHomePage() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHeader('Welcome'),
          const SizedBox(height: 24),
          // Edge-to-edge image with only top/bottom spacing
          SizedBox(
            width: double.infinity,
            child: Image.asset('assets/home.png', fit: BoxFit.cover),
          ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Card(
              color: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Today's Verse",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _todaysVerse['text'] ?? '',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _todaysVerse['reference'] ?? '',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemainderPage() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHeader('Time to Wish'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  color: Colors.white,
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Add New Event",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _nameController,
                          style: const TextStyle(color: Colors.black),
                          decoration: InputDecoration(
                            labelText: 'Event Name',
                            labelStyle: const TextStyle(color: Colors.black),
                            prefixIcon: const Icon(
                              Icons.event,
                              color: Colors.black,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Color(0xFFbbc5cf),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Color(0xFFbbc5cf),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _selectedDate == null
                                    ? 'No date chosen'
                                    : 'Date: ${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(
                                Icons.calendar_today,
                                color: Colors.black,
                              ),
                              label: const Text(
                                'Choose Date',
                                style: TextStyle(color: Colors.black),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.black,
                              ),
                              onPressed: _pickDate,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _selectedTime == null
                                    ? 'No time chosen'
                                    : 'Time: ${_selectedTime!.format(context)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(
                                Icons.access_time,
                                color: Colors.black,
                              ),
                              label: const Text(
                                'Choose Time',
                                style: TextStyle(color: Colors.black),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.black,
                              ),
                              onPressed: _pickTime,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.add, color: Colors.black),
                            label: const Text(
                              'Add Event',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFbbc5cf),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                            onPressed: _addBirthday,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Upcoming Events',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 12),
                _birthdays.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'No events added yet',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _birthdays.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final item = _birthdays[i];
                          final date = item['date'] as DateTime;
                          final time = item['time'] as TimeOfDay;
                          return Card(
                            color: Colors.white,
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFFbbc5cf),
                                child: const Icon(
                                  Icons.event_available,
                                  color: Colors.black,
                                ),
                              ),
                              title: Text(
                                item['name'],
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${date.day}/${date.month}/${date.year} at ${time.format(context)}',
                                style: const TextStyle(color: Colors.black87),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                tooltip: 'Delete Event',
                                onPressed: () => _deleteBirthday(i),
                              ),
                            ),
                          );
                        },
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarPage() {
    return Column(
      children: [
        _buildHeader('Time to Wish'),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              color: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TableCalendar(
                  firstDay: DateTime.utc(2020, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: DateTime.now(),
                  calendarStyle: CalendarStyle(
                    todayDecoration: BoxDecoration(
                      color: Color(0xFFbbc5cf),
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                    weekendTextStyle: TextStyle(color: Colors.black),
                    defaultTextStyle: TextStyle(color: Colors.black),
                  ),
                  headerStyle: HeaderStyle(
                    formatButtonVisible: false,
                    titleCentered: true,
                    titleTextStyle: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
