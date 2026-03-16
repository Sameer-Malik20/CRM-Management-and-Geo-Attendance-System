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
  final TextEditingController _singleEmployeeIdController =
      TextEditingController();
  final TextEditingController _groupEmployeeIdController =
      TextEditingController();

  List<AdminUserProfile> _users = [];
  List<AdminUserProfile> _selectedGroupUsers = <AdminUserProfile>[];
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
    _singleEmployeeIdController.dispose();
    _groupEmployeeIdController.dispose();
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
      setState(() {
        _selectedUser = null;
      });
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

  Future<void> _addGroupUserByEmployeeId([String? explicitEmployeeId]) async {
    final employeeId =
        (explicitEmployeeId ?? _groupEmployeeIdController.text).trim();
    if (employeeId.isEmpty) {
      return;
    }

    final user = await _adminService.getUserByEmployeeId(employeeId);
    if (!mounted) return;

    if (user == null || user.isManager) {
      _showMessage('Employee ID not found.', isError: true);
      return;
    }

    final alreadyAdded = _selectedGroupUsers.any(
      (selected) =>
          selected.employeeId.trim().toLowerCase() ==
          user.employeeId.trim().toLowerCase(),
    );
    if (alreadyAdded) {
      _showMessage('This worker is already selected.');
      _groupEmployeeIdController.clear();
      return;
    }

    if (_selectedGroupUsers.length >= 10) {
      _showMessage('You can select up to 10 workers only.', isError: true);
      return;
    }

    setState(() {
      _selectedGroupUsers = [..._selectedGroupUsers, user];
      _groupEmployeeIdController.clear();
    });
  }

  void _removeGroupUser(AdminUserProfile user) {
    setState(() {
      _selectedGroupUsers = _selectedGroupUsers
          .where((selected) => selected.uid != user.uid)
          .toList();
    });
  }

  Future<void> _openSingleCapturePage(AdminPhotoFlow flow) async {
    final selectedUser = _selectedUser;
    if (flow == AdminPhotoFlow.registerFace && selectedUser == null) {
      _showMessage('Select a worker first.', isError: true);
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => AdminPhotoCapturePage(
          selectedUser: selectedUser,
          candidateUsers: _users,
          markType: _markType,
          flow: flow,
        ),
      ),
    );

    if (changed == true) {
      await _loadUsers();
      if (selectedUser == null) {
        return;
      }
      final refreshedUser =
          await _adminService.getUserByEmployeeId(selectedUser.employeeId);
      if (!mounted) return;
      setState(() {
        _selectedUser = refreshedUser;
      });
    }
  }

  Future<void> _openGroupCapturePage() async {
    final candidateUsers =
        _selectedGroupUsers.isEmpty ? _users : _selectedGroupUsers;
    if (candidateUsers.isEmpty) {
      _showMessage('No workers available for group attendance.', isError: true);
      return;
    }

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => AdminPhotoCapturePage(
          candidateUsers: candidateUsers,
          markType: _markType,
          flow: AdminPhotoFlow.markGroupAttendance,
        ),
      ),
    );

    if (changed == true) {
      await _loadUsers();
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
                    'Choose a single worker manually, or capture a group photo to auto-detect up to 10 workers at once.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 20),
                  _buildSingleWorkerCard(),
                  const SizedBox(height: 20),
                  _buildGroupAttendanceCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildSingleWorkerCard() {
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
          const Text(
            'Single Worker Attendance',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedUser == null
                ? 'Employee ID optional hai. Blank chhodo to captured face jis worker se match hogi, usi ki attendance lag jayegi.'
                : 'Employee ID match locked hai. Is worker ki face match hone par attendance mark hogi.',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _singleEmployeeIdController,
            decoration: InputDecoration(
              labelText: 'Employee ID (Optional)',
              suffixIcon: IconButton(
                onPressed: _lookupSingleUser,
                icon: const Icon(Icons.search),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onChanged: (value) {
              if (value.trim().isEmpty && _selectedUser != null) {
                setState(() {
                  _selectedUser = null;
                });
              }
            },
            onSubmitted: (_) => _lookupSingleUser(),
          ),
          const SizedBox(height: 12),
          if (_selectedUser != null) _buildUserProfileCard(_selectedUser!),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _selectedUser == null
                      ? null
                      : () => _openSingleCapturePage(
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
                  onPressed: () => _openSingleCapturePage(
                    AdminPhotoFlow.markSingleAttendance,
                  ),
                  icon: const Icon(Icons.camera_alt),
                  label: Text(
                    _selectedUser == null
                        ? 'Auto Detect Attendance'
                        : 'Mark Attendance',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupAttendanceCard() {
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
          const Text(
            'Group Attendance',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedGroupUsers.isEmpty
                ? 'No workers selected. The camera will auto-detect up to 10 registered workers from the captured group photo.'
                : 'Selected workers only will be counted from the group photo. You can add up to 10 workers manually.',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _groupEmployeeIdController,
            decoration: InputDecoration(
              labelText: 'Add worker by Employee ID',
              suffixIcon: IconButton(
                onPressed: _addGroupUserByEmployeeId,
                icon: const Icon(Icons.person_add_alt_1),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onSubmitted: (_) => _addGroupUserByEmployeeId(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedGroupUsers.isEmpty
                ? [
                    _emptyChip('Auto-detect up to 10 workers'),
                  ]
                : _selectedGroupUsers
                    .map(
                      (user) => Chip(
                        label: Text('${user.name} (${user.employeeId})'),
                        onDeleted: () => _removeGroupUser(user),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 16),
          if (_users.isNotEmpty) ...[
            const Text(
              'Quick Add',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _users
                  .take(10)
                  .map(
                    (user) => ActionChip(
                      label: Text(user.employeeId),
                      onPressed: () => _addGroupUserByEmployeeId(user.employeeId),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: splashScreenColorTop,
              ),
              onPressed: _openGroupCapturePage,
              icon: const Icon(Icons.groups_2),
              label: const Text('Open Group Attendance Camera'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserProfileCard(AdminUserProfile user) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        borderRadius: BorderRadius.circular(20),
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

  Widget _emptyChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(label),
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
