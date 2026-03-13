import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geo_attendance_system/src/services/admin_service.dart';
import 'package:geo_attendance_system/src/ui/constants/colors.dart';
import 'package:geo_attendance_system/src/ui/pages/admin_photo_capture_page.dart';

class AdminAttendancePage extends StatefulWidget {
  final User currentUser;

  const AdminAttendancePage({super.key, required this.currentUser});

  @override
  State<AdminAttendancePage> createState() => _AdminAttendancePageState();
}

class _AdminAttendancePageState extends State<AdminAttendancePage>
    with SingleTickerProviderStateMixin {
  final AdminService _adminService = AdminService();
  final TextEditingController _singleEmployeeIdController =
      TextEditingController();
  final TextEditingController _groupSearchController = TextEditingController();

  late TabController _tabController;
  List<AdminUserProfile> _users = [];
  AdminUserProfile? _singleUser;
  List<AdminUserProfile> _selectedGroupUsers = [];
  bool _loading = true;
  String _singleMarkType = 'in';
  String _groupMarkType = 'in';
  bool _autoDetectGroupUsers = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUsers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _singleEmployeeIdController.dispose();
    _groupSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
    });
    final users = await _adminService.fetchUsers();
    if (!mounted) return;
    setState(() {
      _users = users.where((user) => !user.isManager).toList();
      _loading = false;
    });
  }

  Future<void> _lookupSingleUser() async {
    final employeeId = _singleEmployeeIdController.text.trim();
    if (employeeId.isEmpty) {
      return;
    }
    final user = await _adminService.getUserByEmployeeId(employeeId);
    if (!mounted) return;
    setState(() {
      _singleUser = user;
    });
    if (user == null) {
      _showMessage("Employee ID not found.", isError: true);
    }
  }

  List<AdminUserProfile> get _filteredGroupUsers {
    final query = _groupSearchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _users;
    }
    return _users.where((user) {
      return user.employeeId.toLowerCase().contains(query) ||
          user.name.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: appbarcolor,
        title: const Text("Admin Attendance"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Single Photo"),
            Tab(text: "Group Photo"),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSinglePhotoTab(),
                _buildGroupPhotoTab(),
              ],
            ),
    );
  }

  Widget _buildSinglePhotoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "An admin can enter any worker's employee ID, load the worker profile, register a face, and mark attendance.",
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _singleEmployeeIdController,
            decoration: InputDecoration(
              labelText: "Employee ID",
              suffixIcon: IconButton(
                onPressed: _lookupSingleUser,
                icon: const Icon(Icons.search),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onSubmitted: (_) => _lookupSingleUser(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _singleMarkType,
            decoration: InputDecoration(
              labelText: "Attendance Type",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            items: const [
              DropdownMenuItem(value: 'in', child: Text('Mark IN')),
              DropdownMenuItem(value: 'out', child: Text('Mark OUT')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _singleMarkType = value;
              });
            },
          ),
          const SizedBox(height: 16),
          if (_singleUser != null) _buildUserProfileCard(_singleUser!),
          if (_singleUser != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openCapturePage(
                      users: [_singleUser!],
                      markType: _singleMarkType,
                      flow: AdminPhotoFlow.registerFace,
                      groupMode: false,
                      autoDetectAll: false,
                    ),
                    icon: const Icon(Icons.face_retouching_natural),
                    label: const Text("Register Face"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: splashScreenColorTop,
                    ),
                    onPressed: () => _openCapturePage(
                      users: [_singleUser!],
                      markType: _singleMarkType,
                      flow: AdminPhotoFlow.markAttendance,
                      groupMode: false,
                      autoDetectAll: false,
                    ),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text("Mark Attendance"),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGroupPhotoTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "In auto-detect mode, the system identifies faces automatically. In manual mode, you can choose up to 10 workers.",
                style: TextStyle(color: Colors.black54),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _autoDetectGroupUsers,
                title: const Text("Auto Detect Faces"),
                subtitle: const Text(
                  "When enabled, 1 to 10 recognized workers will be detected automatically.",
                ),
                onChanged: (value) {
                  setState(() {
                    _autoDetectGroupUsers = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _groupMarkType,
                decoration: InputDecoration(
                  labelText: "Attendance Type",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'in', child: Text('Mark IN')),
                  DropdownMenuItem(value: 'out', child: Text('Mark OUT')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _groupMarkType = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              if (!_autoDetectGroupUsers) ...[
                TextField(
                  controller: _groupSearchController,
                  decoration: InputDecoration(
                    hintText: "Search employee ID or name",
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedGroupUsers
                      .map(
                        (user) => Chip(
                          label: Text("${user.employeeId}"),
                          onDeleted: () {
                            setState(() {
                              _selectedGroupUsers.removeWhere(
                                (selected) => selected.uid == user.uid,
                              );
                            });
                          },
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: splashScreenColorTop,
                  ),
                  onPressed: (!_autoDetectGroupUsers && _selectedGroupUsers.isEmpty)
                      ? null
                      : () => _openCapturePage(
                            users: _autoDetectGroupUsers ? _users : _selectedGroupUsers,
                            markType: _groupMarkType,
                            flow: AdminPhotoFlow.markAttendance,
                            groupMode: true,
                            autoDetectAll: _autoDetectGroupUsers,
                          ),
                  icon: const Icon(Icons.groups_2),
                  label: Text(
                    _autoDetectGroupUsers
                        ? "Capture Auto Group Photo"
                        : "Capture Group Photo (${_selectedGroupUsers.length}/10)",
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_autoDetectGroupUsers)
          const Expanded(
            child: Center(
              child: Text(
                "Auto-detect mode is enabled.\nThe system will identify recognized workers automatically.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _filteredGroupUsers.length,
              itemBuilder: (context, index) {
                final user = _filteredGroupUsers[index];
                final selected =
                    _selectedGroupUsers.any((item) => item.uid == user.uid);
                return CheckboxListTile(
                  value: selected,
                  title: Text(user.name),
                  subtitle: Text("${user.employeeId} | ${user.designation}"),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        if (_selectedGroupUsers.length >= 10) {
                          _showMessage("You can select up to 10 employees.",
                              isError: true);
                          return;
                        }
                        if (!selected) {
                          _selectedGroupUsers.add(user);
                        }
                      } else {
                        _selectedGroupUsers.removeWhere(
                          (item) => item.uid == user.uid,
                        );
                      }
                    });
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildUserProfileCard(AdminUserProfile user) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            user.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text("Employee ID: ${user.employeeId}"),
          Text("Designation: ${user.designation}"),
          Text("Site: ${user.allottedOfficeName}"),
          Text("Face: ${user.faceRegistered ? "Registered" : "Pending"}"),
        ],
      ),
    );
  }

  Future<void> _openCapturePage({
    required List<AdminUserProfile> users,
    required String markType,
    required AdminPhotoFlow flow,
    required bool groupMode,
    required bool autoDetectAll,
  }) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => AdminPhotoCapturePage(
          selectedUsers: users,
          markType: markType,
          groupMode: groupMode,
          autoDetectAll: autoDetectAll,
          flow: flow,
        ),
      ),
    );
    if (changed == true) {
      await _loadUsers();
      if (_singleUser != null) {
        _singleUser =
            await _adminService.getUserByEmployeeId(_singleUser!.employeeId);
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : dashBoardColor,
      ),
    );
  }
}
