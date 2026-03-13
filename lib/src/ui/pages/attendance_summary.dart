import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geo_attendance_system/src/models/AttendaceList.dart';
import 'package:geo_attendance_system/src/services/fetch_attendance.dart';
import 'package:geo_attendance_system/src/ui/constants/colors.dart';
import 'package:geo_attendance_system/src/ui/constants/attendance_type.dart';
import 'package:geo_attendance_system/src/ui/widgets/loader_dialog.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:table_calendar/table_calendar.dart';

final Map<DateTime, List> _holidays = {
  DateTime(2019, 1, 1): ['New Year\'s Day'],
  DateTime(2019, 12, 25): ['Christmas Eve'],
};

class AttendanceSummary extends StatefulWidget {
  const AttendanceSummary({Key? key, required this.title, required this.user})
      : super(key: key);

  final String title;
  final User user;

  @override
  _AttendanceSummaryState createState() => _AttendanceSummaryState();
}

class _AttendanceSummaryState extends State<AttendanceSummary> {
  late DateTime _selectedDay;
  late DateTime _focusedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  List<String> _historyItems = [];
  bool _isLoadingHistory = true;
  bool _isRangeMode = false;
  String _historyHeading = "Today's Attendance";
  DateTimeRange? _selectedRange;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting();
    _selectedDay = _normalizeDate(DateTime.now());
    _focusedDay = _selectedDay;
    _loadDayHistory(_selectedDay);
  }

  Future<void> _loadDayHistory(
    DateTime day, {
    bool showLoader = false,
  }) async {
    if (showLoader) {
      onLoadingDialog(context);
    }

    final normalizedDay = _normalizeDate(day);
    try {
      final attendanceList =
          await AttendanceDatabase.getAttendanceListOfParticularDateBasedOnUID(
        widget.user.uid,
        normalizedDay,
      );

      if (!mounted) return;
      setState(() {
        _selectedDay = normalizedDay;
        _focusedDay = normalizedDay;
        _selectedRange = null;
        _isRangeMode = false;
        _historyItems = _formatDayAttendance(attendanceList);
        _historyHeading = _isSameDate(normalizedDay, _normalizeDate(DateTime.now()))
            ? "Today's Attendance"
            : "Attendance on ${getFormattedDate(normalizedDay)}";
        _isLoadingHistory = false;
      });
    } finally {
      if (showLoader && mounted) {
        Navigator.of(context, rootNavigator: true).pop('dialog');
      }
    }
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: _selectedRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: dashBoardColor),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (range == null) {
      return;
    }

    onLoadingDialog(context);
    try {
      final attendanceLists =
          await AttendanceDatabase.getAttendanceListsForDateRangeBasedOnUID(
        widget.user.uid,
        range.start,
        range.end,
      );

      if (!mounted) return;
      setState(() {
        _selectedRange = range;
        _isRangeMode = true;
        _historyItems = _formatRangeAttendance(attendanceLists);
        _historyHeading =
            "Range: ${getFormattedDate(range.start)} to ${getFormattedDate(range.end)}";
        _isLoadingHistory = false;
      });
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop('dialog');
      }
    }
  }

  List<String> _formatDayAttendance(AttendanceList attendanceList) {
    final items = List<Attendance>.from(attendanceList.attendanceList)
      ..sort((a, b) => a.time.compareTo(b.time));

    return items.map((attendance) {
      return "${attendance.type == attendanceType.IN ? "IN" : "OUT"} at ${_formatTime(attendance.time)} | ${attendance.office}";
    }).toList();
  }

  List<String> _formatRangeAttendance(List<AttendanceList> attendanceLists) {
    final result = <String>[];
    for (final attendanceList in attendanceLists) {
      final dayItems = _formatDayAttendance(attendanceList);
      for (final item in dayItems) {
        result.add("${getFormattedDate(attendanceList.dateTime)} | $item");
      }
    }
    return result;
  }

  DateTime _normalizeDate(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  bool _isSameDate(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final meridiem = dateTime.hour >= 12 ? 'PM' : 'AM';
    return "$hour:$minute $meridiem";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: appbarcolor,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          "Attendance History",
          style: TextStyle(
            color: Colors.white,
            fontFamily: "Poppins-Medium",
            fontSize: 22,
            letterSpacing: .6,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0.8,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Container(
          color: dashBoardColor,
          child: Column(
            children: <Widget>[
              _buildTableCalendar(),
              const SizedBox(height: 8.0),
              _buildControls(),
              const SizedBox(height: 8.0),
              Expanded(child: _buildHistoryList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableCalendar() {
    return TableCalendar(
      locale: 'en_US',
      focusedDay: _focusedDay,
      firstDay: DateTime(2000),
      lastDay: DateTime.now(),
      selectedDayPredicate: (day) => _isSameDate(day, _selectedDay),
      onDaySelected: (selectedDay, focusedDay) {
        _focusedDay = focusedDay;
        _loadDayHistory(selectedDay, showLoader: true);
      },
      holidayPredicate: (dateTime) => _holidays.containsKey(
        DateTime(dateTime.year, dateTime.month, dateTime.day),
      ),
      calendarFormat: _calendarFormat,
      formatAnimationCurve: Curves.fastOutSlowIn,
      formatAnimationDuration: const Duration(milliseconds: 400),
      startingDayOfWeek: StartingDayOfWeek.sunday,
      availableGestures: AvailableGestures.all,
      availableCalendarFormats: const {
        CalendarFormat.month: '',
        CalendarFormat.week: '',
      },
      calendarStyle: CalendarStyle(
        outsideDaysVisible: true,
        defaultTextStyle: const TextStyle(color: Colors.white),
        weekendTextStyle: const TextStyle(color: Colors.grey),
        holidayTextStyle: const TextStyle(color: Colors.white),
        outsideTextStyle: const TextStyle(color: Colors.grey),
        selectedDecoration: const BoxDecoration(
          color: Colors.amber,
          shape: BoxShape.circle,
        ),
        todayDecoration: const BoxDecoration(
          color: Color.fromRGBO(29, 209, 161, 1.0),
          shape: BoxShape.circle,
        ),
      ),
      daysOfWeekStyle: const DaysOfWeekStyle(
        weekdayStyle: TextStyle(color: Colors.white),
        weekendStyle: TextStyle(color: Colors.white),
      ),
      headerStyle: const HeaderStyle(
        leftChevronIcon: Icon(Icons.chevron_left, color: Colors.white60),
        rightChevronIcon: Icon(Icons.chevron_right, color: Colors.white60),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 28,
        ),
        titleCentered: true,
        formatButtonVisible: false,
      ),
    );
  }

  Widget _buildControls() {
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            ElevatedButton(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(Colors.indigo),
              ),
              child: const Text('Month', style: TextStyle(color: Colors.white)),
              onPressed: () {
                if (_calendarFormat != CalendarFormat.month) {
                  setState(() {
                    _calendarFormat = CalendarFormat.month;
                  });
                }
              },
            ),
            ElevatedButton(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(Colors.redAccent),
              ),
              child: const Text('Week', style: TextStyle(color: Colors.white)),
              onPressed: () {
                if (_calendarFormat != CalendarFormat.week) {
                  setState(() {
                    _calendarFormat = CalendarFormat.week;
                  });
                }
              },
            ),
            ElevatedButton(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(Colors.teal),
              ),
              onPressed: _pickDateRange,
              child: const Text(
                'Date Range',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12.0),
        if (_isRangeMode)
          TextButton(
            onPressed: () => _loadDayHistory(DateTime.now(), showLoader: true),
            child: const Text(
              "Back To Today",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Text(
          _historyHeading.toUpperCase(),
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4.0),
        const Text(
          "Today loads automatically. Select a date or date range to view older history.",
          style: TextStyle(color: Colors.white54),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildHistoryList() {
    if (_isLoadingHistory) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_historyItems.isEmpty) {
      return Center(
        child: Text(
          _isRangeMode
              ? "No attendance records were found for the selected range."
              : "No attendance records were found for today.",
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 20,
            fontFamily: "Poppins-Medium",
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _historyItems.length,
      itemBuilder: (context, index) {
        final event = _historyItems[index];
        return Container(
          decoration: BoxDecoration(
            border: Border.all(width: 2, color: Colors.white),
            borderRadius: BorderRadius.circular(12.0),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: ListTile(
            title: Text(
              event,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      },
    );
  }
}
