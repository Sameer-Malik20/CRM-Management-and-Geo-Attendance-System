import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geo_attendance_system/src/models/office.dart';
import 'package:geo_attendance_system/src/services/admin_service.dart';
import 'package:geo_attendance_system/src/ui/constants/colors.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:path_provider/path_provider.dart';

class AdminConsolePage extends StatefulWidget {
  final User currentUser;

  const AdminConsolePage({super.key, required this.currentUser});

  @override
  State<AdminConsolePage> createState() => _AdminConsolePageState();
}

class _AdminConsolePageState extends State<AdminConsolePage>
    with SingleTickerProviderStateMixin {
  final AdminService _adminService = AdminService();

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _createNameController = TextEditingController();
  final TextEditingController _createEmployeeIdController =
      TextEditingController();
  final TextEditingController _createEmailController = TextEditingController();
  final TextEditingController _createPasswordController =
      TextEditingController();
  final TextEditingController _createPhoneController = TextEditingController();
  final TextEditingController _createAddressController =
      TextEditingController();
  final TextEditingController _createDesignationController =
      TextEditingController();

  late TabController _tabController;

  List<AdminUserProfile> _users = [];
  List<Office> _sites = [];
  bool _loading = true;
  bool _creatingUser = false;
  bool _exportingCsv = false;
  bool _createAsManager = false;
  String _searchQuery = '';
  String? _selectedSiteKey;
  String? _selectedManagerUid;
  AdminUserProfile? _currentAdminProfile;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _refreshData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _createNameController.dispose();
    _createEmployeeIdController.dispose();
    _createEmailController.dispose();
    _createPasswordController.dispose();
    _createPhoneController.dispose();
    _createAddressController.dispose();
    _createDesignationController.dispose();
    super.dispose();
  }

  List<AdminUserProfile> get _managerUsers =>
      _users.where((user) => user.isManager).toList();

  List<AdminUserProfile> get _filteredUsers {
    if (_searchQuery.trim().isEmpty) {
      return _users;
    }
    final query = _searchQuery.toLowerCase();
    return _users.where((user) {
      return user.name.toLowerCase().contains(query) ||
          user.employeeId.toLowerCase().contains(query) ||
          user.email.toLowerCase().contains(query) ||
          user.allottedOfficeName.toLowerCase().contains(query) ||
          user.designation.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: appbarcolor,
          title: const Text("Admin Console"),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: "Users"),
              Tab(text: "Sites"),
              Tab(text: "Create"),
            ],
          ),
          actions: [
            if (_currentAdminProfile?.isSuperAdmin == true)
              IconButton(
                onPressed: _exportingCsv ? null : _exportCsv,
                icon: _exportingCsv
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.file_download_outlined),
              ),
            IconButton(
              onPressed: _refreshData,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildUsersTab(),
                  _buildSitesTab(),
                  _buildCreateUserTab(),
                ],
              ),
      ),
    );
  }

  Future<void> _refreshData() async {
    setState(() {
      _loading = true;
    });

    try {
      final users = await _adminService.fetchUsers();
      final sites = await _adminService.fetchSites();
      if (!mounted) return;

      final managerUsers = users.where((user) => user.isManager).toList();
      final defaultManager = managerUsers.firstWhere(
        (user) => user.uid == widget.currentUser.uid,
        orElse: () => managerUsers.isNotEmpty
            ? managerUsers.first
            : const AdminUserProfile(
                uid: '',
                employeeId: '',
                name: '',
                email: '',
                phoneNumber: '',
                address: '',
                designation: '',
                allottedOffice: '',
                allottedOfficeName: '',
                managerUid: '',
                isManager: false,
                isSuperAdmin: false,
                faceRegistered: false,
              ),
      );

      setState(() {
        _users = users;
        _sites = sites;
        _currentAdminProfile = users.where((user) => user.uid == widget.currentUser.uid).isNotEmpty
            ? users.firstWhere((user) => user.uid == widget.currentUser.uid)
            : null;
        _selectedSiteKey =
            _selectedSiteKey ?? (sites.isNotEmpty ? sites.first.key : null);
        _selectedManagerUid = _selectedManagerUid ?? defaultManager.uid;
      });
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Widget _buildUsersTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: "Search user, employee ID, site, email",
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Total users: ${_filteredUsers.length}",
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _filteredUsers.isEmpty
              ? const Center(child: Text("No users found."))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: _filteredUsers.length,
                  itemBuilder: (context, index) {
                    final user = _filteredUsers[index];
                    return _buildUserCard(user);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSitesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Manage site records here, including creation, editing, and latitude/longitude allocation.",
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: splashScreenColorTop,
                  ),
                  onPressed: () => _openSiteSheet(),
                  icon: const Icon(Icons.add_location_alt),
                  label: const Text("Add Site"),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _sites.isEmpty
              ? const Center(child: Text("No sites found."))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _sites.length,
                  itemBuilder: (context, index) {
                    final site = _sites[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 14,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: CircleAvatar(
                          backgroundColor: Colors.blueGrey.shade50,
                          child: const Icon(Icons.location_city),
                        ),
                        title: Text(
                          site.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            "Lat: ${site.latitude}\nLng: ${site.longitude}\nRadius: ${site.radius.toStringAsFixed(0)} m",
                          ),
                        ),
                        trailing: IconButton(
                          onPressed: () => _openSiteSheet(site: site),
                          icon: const Icon(Icons.edit_location_alt),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCreateUserTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Create Credentials",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              "Create admin or employee login credentials here. Email is optional. If left blank, the system will generate one automatically, which is useful for workers without smartphones.",
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _createAsManager,
              title: const Text("Create as Admin / Manager"),
              subtitle: const Text(
                "When enabled, this user will receive admin access and the admin console in the drawer.",
              ),
              onChanged: _canCreateAdmins
                  ? (value) {
                setState(() {
                  _createAsManager = value;
                });
              }
                  : null,
            ),
            if (!_canCreateAdmins)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  "A limited admin can create employees only. Creating another admin is restricted to the super admin.",
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            const SizedBox(height: 8),
            _inputField(_createNameController, "Full Name"),
            _inputField(_createEmployeeIdController, "Employee ID"),
            _inputField(_createEmailController, "Email (Optional)"),
            _inputField(
              _createPasswordController,
              "Password",
              obscureText: true,
            ),
            _inputField(_createPhoneController, "Phone Number"),
            _inputField(_createDesignationController, "Designation"),
            _inputField(_createAddressController, "Address", maxLines: 2),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedSiteKey,
              decoration: _dropdownDecoration("Allocate Site"),
              items: _sites
                  .map(
                    (site) => DropdownMenuItem<String>(
                      value: site.key,
                      child: Text(site.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedSiteKey = value;
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _createAsManager
                  ? '__self__'
                  : (_selectedManagerUid ?? widget.currentUser.uid),
              decoration: _dropdownDecoration("Reporting Manager"),
              items: [
                if (_createAsManager)
                  const DropdownMenuItem<String>(
                    value: '__self__',
                    child: Text("Self Managed Admin"),
                  ),
                ..._managerUsers.map(
                  (user) => DropdownMenuItem<String>(
                    value: user.uid,
                    child: Text("${user.name} (${user.employeeId})"),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedManagerUid = value == '__self__' ? '' : value;
                });
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: splashScreenColorTop,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _creatingUser ? null : _createUser,
                icon: _creatingUser
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.person_add_alt_1),
                label: Text(
                  _creatingUser ? "Creating..." : "Create Login Credentials",
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(AdminUserProfile user) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name.isEmpty ? user.employeeId : user.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${user.employeeId} | ${user.email}",
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: splashScreenColorTop,
                  ),
                  onPressed: () => _openEditUserSheet(user),
                  icon: const Icon(Icons.edit),
                  label: const Text("Edit"),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _infoChip(
                  user.isManager ? "Admin / Manager" : "Employee",
                  user.isManager ? Colors.indigo : Colors.teal,
                ),
                if (user.isSuperAdmin)
                  _infoChip(
                    "Super Admin",
                    Colors.deepPurple,
                  ),
                _infoChip(
                  user.faceRegistered ? "Face Registered" : "Face Pending",
                  user.faceRegistered ? Colors.green : Colors.orange,
                ),
                _infoChip(
                  user.allottedOfficeName.isEmpty
                      ? "No Site"
                      : user.allottedOfficeName,
                  Colors.blueGrey,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text("Designation: ${user.designation}"),
            Text("Phone: ${user.phoneNumber}"),
            Text("Address: ${user.address}"),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _inputField(
    TextEditingController controller,
    String label, {
    bool obscureText = false,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.blueGrey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  InputDecoration _dropdownDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.blueGrey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    );
  }

  Future<void> _createUser() async {
    if (_sites.isEmpty) {
      _showMessage("Please create a site first.", isError: true);
      _tabController.animateTo(1);
      return;
    }

    if (_createNameController.text.trim().isEmpty ||
        _createEmployeeIdController.text.trim().isEmpty ||
        _createPasswordController.text.trim().isEmpty ||
        _createDesignationController.text.trim().isEmpty ||
        _selectedSiteKey == null) {
      _showMessage("Please complete all required fields.", isError: true);
      return;
    }

    setState(() {
      _creatingUser = true;
    });

    try {
      final managerUid = _createAsManager
          ? ''
          : (_selectedManagerUid == null || _selectedManagerUid!.isEmpty
              ? widget.currentUser.uid
              : _selectedManagerUid!);

      final user = await _adminService.createUser(
        AdminCreateUserRequest(
          employeeId: _createEmployeeIdController.text.trim(),
          name: _createNameController.text.trim(),
          email: _createEmailController.text.trim(),
          password: _createPasswordController.text,
          phoneNumber: _createPhoneController.text.trim(),
          address: _createAddressController.text.trim(),
          designation: _createDesignationController.text.trim(),
          allottedOffice: _selectedSiteKey!,
          managerUid: managerUid,
          isManager: _createAsManager,
          isSuperAdmin: false,
        ),
      );

      _showMessage(
        "User created: ${user.employeeId} / ${_createPasswordController.text}",
      );
      setState(_clearCreateForm);
      await _refreshData();
      _tabController.animateTo(0);
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _creatingUser = false;
        });
      }
    }
  }

  void _clearCreateForm() {
    _createNameController.clear();
    _createEmployeeIdController.clear();
    _createEmailController.clear();
    _createPasswordController.clear();
    _createPhoneController.clear();
    _createAddressController.clear();
    _createDesignationController.clear();
    _createAsManager = false;
    _selectedManagerUid = widget.currentUser.uid;
  }

  Future<LatLng?> _getCurrentGpsCoordinates() async {
    final location = Location();
    var serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
    }
    if (!serviceEnabled) {
      return null;
    }

    var permissionStatus = await location.hasPermission();
    if (permissionStatus == PermissionStatus.denied) {
      permissionStatus = await location.requestPermission();
    }
    if (permissionStatus != PermissionStatus.granted) {
      return null;
    }

    final currentLocation = await location.getLocation();
    final latitude = currentLocation.latitude;
    final longitude = currentLocation.longitude;
    if (latitude == null || longitude == null) {
      return null;
    }

    return LatLng(latitude, longitude);
  }

  Future<void> _openSiteSheet({Office? site}) async {
    final nameController = TextEditingController(text: site?.name ?? '');
    final latitudeController =
        TextEditingController(text: site?.latitude.toString() ?? '');
    final longitudeController =
        TextEditingController(text: site?.longitude.toString() ?? '');
    final radiusController = TextEditingController(
      text: site != null ? site.radius.toStringAsFixed(0) : '200',
    );
    LatLng selectedCoordinates = LatLng(
      site?.latitude ?? 28.6139,
      site?.longitude ?? 77.2090,
    );
    LatLng? currentGpsCoordinates;
    GoogleMapController? mapController;
    var isFetchingGps = site == null;

    if (site == null) {
      latitudeController.text = selectedCoordinates.latitude.toStringAsFixed(6);
      longitudeController.text = selectedCoordinates.longitude.toStringAsFixed(6);
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> fetchGpsIfNeeded() async {
              if (!isFetchingGps) {
                return;
              }

              final gpsCoordinates = await _getCurrentGpsCoordinates();
              if (!context.mounted) {
                return;
              }

              setModalState(() {
                isFetchingGps = false;
                currentGpsCoordinates = gpsCoordinates;
                if (site == null && gpsCoordinates != null) {
                  selectedCoordinates = gpsCoordinates;
                  latitudeController.text =
                      gpsCoordinates.latitude.toStringAsFixed(6);
                  longitudeController.text =
                      gpsCoordinates.longitude.toStringAsFixed(6);
                }
              });

              if (site == null && gpsCoordinates != null) {
                await mapController?.animateCamera(
                  CameraUpdate.newCameraPosition(
                    CameraPosition(target: gpsCoordinates, zoom: 17),
                  ),
                );
              }
            }

            if (isFetchingGps) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                fetchGpsIfNeeded();
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      site == null ? "Add Site" : "Edit Site",
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isFetchingGps
                          ? "Form is ready. Current GPS is being fetched in the background. You can still zoom, pan, and pick a custom location right away."
                          : currentGpsCoordinates == null
                          ? "Tap the map to pick the exact site location, then set the attendance radius in meters."
                          : "Current GPS has been detected automatically. You can zoom, pan, or tap anywhere on the map to pick a custom location.",
                      style: const TextStyle(color: Colors.black54),
                    ),
                    if (isFetchingGps)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(
                        height: 240,
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: selectedCoordinates,
                            zoom: site == null ? 14 : 16,
                          ),
                          onMapCreated: (controller) {
                            mapController = controller;
                          },
                          gestureRecognizers: {
                            Factory<OneSequenceGestureRecognizer>(
                              () => EagerGestureRecognizer(),
                            ),
                          },
                          markers: {
                            Marker(
                              markerId: const MarkerId('selected-site'),
                              position: selectedCoordinates,
                              infoWindow: const InfoWindow(
                                title: 'Selected Site Location',
                              ),
                            ),
                          },
                          circles: {
                            Circle(
                              circleId: const CircleId('site-radius'),
                              center: selectedCoordinates,
                              radius:
                                  double.tryParse(radiusController.text.trim()) ??
                                      200,
                              strokeColor: splashScreenColorTop,
                              strokeWidth: 2,
                              fillColor: splashScreenColorTop.withOpacity(0.12),
                            ),
                          },
                          onTap: (value) {
                            setModalState(() {
                              selectedCoordinates = value;
                              latitudeController.text =
                                  value.latitude.toStringAsFixed(6);
                              longitudeController.text =
                                  value.longitude.toStringAsFixed(6);
                            });
                          },
                          zoomControlsEnabled: true,
                          zoomGesturesEnabled: true,
                          scrollGesturesEnabled: true,
                          rotateGesturesEnabled: true,
                          tiltGesturesEnabled: true,
                          myLocationEnabled: currentGpsCoordinates != null,
                          myLocationButtonEnabled: currentGpsCoordinates != null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (currentGpsCoordinates != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            final gpsCoordinates = currentGpsCoordinates!;
                            setModalState(() {
                              selectedCoordinates = gpsCoordinates;
                              latitudeController.text = gpsCoordinates
                                  .latitude
                                  .toStringAsFixed(6);
                              longitudeController.text = gpsCoordinates
                                  .longitude
                                  .toStringAsFixed(6);
                            });
                            await mapController?.animateCamera(
                              CameraUpdate.newCameraPosition(
                                CameraPosition(
                                  target: gpsCoordinates,
                                  zoom: 17,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.my_location),
                          label: const Text("Use Current GPS"),
                        ),
                      ),
                    _inputField(nameController, "Site Name"),
                    Row(
                      children: [
                        Expanded(
                          child: _inputField(latitudeController, "Latitude"),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _inputField(longitudeController, "Longitude"),
                        ),
                      ],
                    ),
                    _inputField(radiusController, "Radius (meters)"),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          setModalState(() {
                            latitudeController.text =
                                selectedCoordinates.latitude.toStringAsFixed(6);
                            longitudeController.text =
                                selectedCoordinates.longitude.toStringAsFixed(6);
                          });
                        },
                        icon: const Icon(Icons.place),
                        label: const Text("Use Selected Map Location"),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: splashScreenColorTop,
                        ),
                        onPressed: () async {
                          final latitude =
                              double.tryParse(latitudeController.text.trim());
                          final longitude =
                              double.tryParse(longitudeController.text.trim());
                          final radius =
                              double.tryParse(radiusController.text.trim());
                          if (nameController.text.trim().isEmpty ||
                              latitude == null ||
                              longitude == null ||
                              radius == null ||
                              radius <= 0) {
                            _showMessage(
                              "Please enter valid site details.",
                              isError: true,
                            );
                            return;
                          }

                          try {
                            await _adminService.saveSite(
                              siteKey: site?.key,
                              name: nameController.text.trim(),
                              latitude: latitude,
                              longitude: longitude,
                              radius: radius,
                            );
                            if (!mounted) return;
                            Navigator.of(context).pop();
                            _showMessage("Site saved successfully.");
                            await _refreshData();
                          } catch (error) {
                            _showMessage(error.toString(), isError: true);
                          }
                        },
                        child: Text(site == null ? "Create Site" : "Save Site"),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openEditUserSheet(AdminUserProfile user) async {
    final nameController = TextEditingController(text: user.name);
    final employeeIdController = TextEditingController(text: user.employeeId);
    final phoneController = TextEditingController(text: user.phoneNumber);
    final addressController = TextEditingController(text: user.address);
    final designationController = TextEditingController(text: user.designation);
    final emailController = TextEditingController(text: user.email);

    var selectedOffice = user.allottedOffice;
    var selectedManager = user.managerUid;
    var isManager = user.isManager;
    var isSuperAdmin = user.isSuperAdmin;
    var faceRegistered = user.faceRegistered;
    final canManageThisUserAdminRole = _canCreateAdmins || !user.isManager;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Edit User Profile",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _inputField(nameController, "Full Name"),
                    _inputField(employeeIdController, "Employee ID"),
                    _inputField(emailController, "Email"),
                    _inputField(phoneController, "Phone Number"),
                    _inputField(designationController, "Designation"),
                    _inputField(addressController, "Address", maxLines: 2),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: isManager,
                      title: const Text("Admin / Manager Access"),
                      subtitle: const Text(
                        "When enabled, this user will be able to open the admin console.",
                      ),
                      onChanged: canManageThisUserAdminRole
                          ? (value) {
                        setModalState(() {
                          isManager = value;
                          if (value) {
                            selectedManager = '';
                          }
                        });
                      }
                          : null,
                    ),
                    if (_canCreateAdmins)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: isSuperAdmin,
                        title: const Text("Super Admin Access"),
                        subtitle: const Text(
                          "This user will be allowed to create and manage other admins.",
                        ),
                        onChanged: isManager
                            ? (value) {
                                setModalState(() {
                                  isSuperAdmin = value;
                                });
                              }
                            : null,
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: faceRegistered,
                      title: const Text("Face Registered"),
                      subtitle: const Text(
                        "Admins can also reset face registration status from here when needed.",
                      ),
                      onChanged: (value) {
                        setModalState(() {
                          faceRegistered = value;
                        });
                      },
                    ),
                    DropdownButtonFormField<String>(
                      value: selectedOffice.isEmpty && _sites.isNotEmpty
                          ? _sites.first.key
                          : selectedOffice,
                      decoration: _dropdownDecoration("Allocated Site"),
                      items: _sites
                          .map(
                            (site) => DropdownMenuItem<String>(
                              value: site.key,
                              child: Text(site.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setModalState(() {
                          selectedOffice = value ?? selectedOffice;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: isManager
                          ? '__self__'
                          : (selectedManager.isEmpty
                              ? widget.currentUser.uid
                              : selectedManager),
                      decoration: _dropdownDecoration("Reporting Manager"),
                      items: [
                        if (isManager)
                          const DropdownMenuItem<String>(
                            value: '__self__',
                            child: Text("Self Managed Admin"),
                          ),
                        ..._managerUsers.map(
                          (manager) => DropdownMenuItem<String>(
                            value: manager.uid,
                            child: Text(
                              "${manager.name} (${manager.employeeId})",
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setModalState(() {
                          selectedManager =
                              value == '__self__' ? '' : (value ?? '');
                        });
                      },
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: splashScreenColorTop,
                        ),
                        onPressed: () async {
                          if (employeeIdController.text.trim().isEmpty ||
                              nameController.text.trim().isEmpty ||
                              emailController.text.trim().isEmpty ||
                              selectedOffice.isEmpty) {
                            _showMessage(
                              "Required profile fields are missing.",
                              isError: true,
                            );
                            return;
                          }

                          final updated = user.copyWith(
                            employeeId: employeeIdController.text.trim(),
                            name: nameController.text.trim(),
                            email: emailController.text.trim(),
                            phoneNumber: phoneController.text.trim(),
                            address: addressController.text.trim(),
                            designation: designationController.text.trim(),
                            allottedOffice: selectedOffice,
                            allottedOfficeName: _sites
                                    .where((site) => site.key == selectedOffice)
                                    .map((site) => site.name)
                                    .cast<String?>()
                                    .firstWhere(
                                      (name) => name != null,
                                      orElse: () => selectedOffice,
                                    ) ??
                                selectedOffice,
                            managerUid: isManager
                                ? ''
                                : (selectedManager.isEmpty
                                    ? widget.currentUser.uid
                                    : selectedManager),
                            isManager: isManager,
                            isSuperAdmin: isManager ? isSuperAdmin : false,
                            faceRegistered: faceRegistered,
                          );

                          try {
                            await _adminService.updateUser(
                              profile: updated,
                              previousEmployeeId: user.employeeId,
                              previousManagerUid: user.managerUid,
                            );
                            if (!mounted) return;
                            Navigator.of(bottomSheetContext).pop();
                            _showMessage("User profile updated.");
                            await _refreshData();
                          } catch (error) {
                            _showMessage(error.toString(), isError: true);
                          }
                        },
                        icon: const Icon(Icons.save),
                        label: const Text("Save Changes"),
                      ),
                    ),
                    if (user.uid != widget.currentUser.uid &&
                        (_canCreateAdmins || !user.isManager))
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              try {
                                await _adminService.deleteUser(user);
                                if (!mounted) return;
                                Navigator.of(bottomSheetContext).pop();
                                _showMessage("User deleted successfully.");
                                await _refreshData();
                              } catch (error) {
                                _showMessage(error.toString(), isError: true);
                              }
                            },
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            label: const Text(
                              "Delete User",
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _exportCsv() async {
    setState(() {
      _exportingCsv = true;
    });

    try {
      final csv = await _adminService.exportFullCsv();
      final directory = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final exportDirectory = Directory('${directory.path}/exports');
      if (!await exportDirectory.exists()) {
        await exportDirectory.create(recursive: true);
      }

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final file =
          File('${exportDirectory.path}/susageo_export_$timestamp.csv');
      await file.writeAsString(csv);
      _showMessage('CSV exported to ${file.path}');
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _exportingCsv = false;
        });
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message.replaceFirst('Exception: ', '')),
        backgroundColor: isError ? Colors.redAccent : dashBoardColor,
      ),
    );
  }

  bool get _canCreateAdmins => _currentAdminProfile?.isSuperAdmin == true;
}
