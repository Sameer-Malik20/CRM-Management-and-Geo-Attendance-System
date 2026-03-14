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

class _AdminAttendancePageState extends State<AdminAttendancePage> {
  final AdminService _adminService = AdminService();
  final TextEditingController _employeeIdController = TextEditingController();

  List<AdminUserProfile> _users = [];
  AdminUserProfile? _selectedUser;
  bool _loading = true;
  String _markType = 'in';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _employeeIdController.dispose();
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

  Future<void> _lookupUser() async {
    final employeeId = _employeeIdController.text.trim();
    if (employeeId.isEmpty) {
      return;
    }
    final user = await _adminService.getUserByEmployeeId(employeeId);
    if (!mounted) return;
    setState(() {
      _selectedUser = user;
    });
    if (user == null) {
      _showMessage('Employee ID not found.', isError: true);
    }
  }

  Future<void> _openCapturePage(AdminPhotoFlow flow) async {
    final selectedUser = _selectedUser;
    if (selectedUser == null) {
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => AdminPhotoCapturePage(
          selectedUser: selectedUser,
          markType: _markType,
          flow: flow,
        ),
      ),
    );

    if (changed == true) {
      await _loadUsers();
      final refreshedUser =
          await _adminService.getUserByEmployeeId(selectedUser.employeeId);
      if (!mounted) return;
      setState(() {
        _selectedUser = refreshedUser;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: appbarcolor,
        title: const Text('Admin Attendance'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Use a single face-lock style photo flow for registration and attendance.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _employeeIdController,
                    decoration: InputDecoration(
                      labelText: 'Employee ID',
                      suffixIcon: IconButton(
                        onPressed: _lookupUser,
                        icon: const Icon(Icons.search),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onSubmitted: (_) => _lookupUser(),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _markType,
                    decoration: InputDecoration(
                      labelText: 'Attendance Type',
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
                        _markType = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_selectedUser != null)
                    _buildUserProfileCard(_selectedUser!),
                  if (_selectedUser != null) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _openCapturePage(
                              AdminPhotoFlow.registerFace,
                            ),
                            icon: const Icon(Icons.face_retouching_natural),
                            label: const Text('Register Face'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: splashScreenColorTop,
                            ),
                            onPressed: () => _openCapturePage(
                              AdminPhotoFlow.markAttendance,
                            ),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Mark Attendance'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_selectedUser == null && _users.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Recent Workers',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    ..._users.take(8).map(
                          (user) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(user.name),
                            subtitle: Text(
                                '${user.employeeId} | ${user.designation}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              _employeeIdController.text = user.employeeId;
                              _lookupUser();
                            },
                          ),
                        ),
                  ],
                ],
              ),
            ),
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
          Text('Employee ID: ${user.employeeId}'),
          Text('Designation: ${user.designation}'),
          Text('Site: ${user.allottedOfficeName}'),
          Text('Face: ${user.faceRegistered ? "Registered" : "Pending"}'),
        ],
      ),
    );
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
