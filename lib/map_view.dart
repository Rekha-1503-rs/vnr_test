import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import 'Controller/punch_in_controller.dart';

class MapViewScreen extends StatefulWidget {
  const MapViewScreen({super.key});

  @override
  State<MapViewScreen> createState() => _MapViewScreenState();
}

class _MapViewScreenState extends State<MapViewScreen> {
  final PunchController controller = Get.find<PunchController>();
  final MapController mapController = MapController();

  LatLng? currentLatLng;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      return;
    }

    // ✅ Get current location
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    _updatePosition(position);

    // ✅ Live location updates
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      _updatePosition(pos);
    });
  }

  void _updatePosition(Position pos) {
    setState(() {
      currentLatLng = LatLng(pos.latitude, pos.longitude);
    });

    if (mapController.camera != null) {
      mapController.move(currentLatLng!, 16);
    }
  }

  @override
  Widget build(BuildContext context) {
    final punches = controller.recentPunches.reversed.toList();

    LatLng center = currentLatLng ??
        (punches.isNotEmpty
            ? LatLng(punches.first.latitude, punches.first.longitude)
            : LatLng(controller.designatedLat, controller.designatedLng));

    return Scaffold(
      appBar: AppBar(
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),
        title: const Text(
          "Map View",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blueAccent,
      ),
      body: FlutterMap(
        mapController: mapController,
        options: MapOptions(
          initialCenter: center,
          initialZoom: 16,
        ),
        children: [
          TileLayer(
            urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
          ),
          MarkerLayer(
            markers: [
              if (currentLatLng != null)
                Marker(
                  point: currentLatLng!,
                  width: 50,
                  height: 50,
                  child: const Icon(
                    Icons.my_location,
                    color: Colors.blue,
                    size: 40,
                  ),
                ),
            ],
          )
        ],
      ),
    );
  }
}
/*import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../Models/punch_in_model.dart';
import '../db_helper/db_helper.dart';

class PunchController extends GetxController {
  final double designatedLat = 22.734305;
  final double designatedLng = 75.882556;

  var currentPosition = Rxn<Position>();
  var currentDistance = 0.0.obs;
  var isWithinRadius = false.obs;
  var isPunching = false.obs;
  var isMocked = false.obs;

  var recentPunches = <Punch>[].obs;
  var groupedPunches = <String, List<Punch>>{}.obs;

  DateTime? lastPunchTime;

  @override
  void onInit() {
    super.onInit();
    initLocation();
    loadRecentPunches();
    loadLastNDaysGrouped(days: 5);
  }

  Future<bool> hasInternet() async {
    var result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  Future<bool> checkMockLocation(Position pos) async {
    try {
      if (pos.isMocked) return true;
    } catch (_) {}
    const platform = MethodChannel("mock-location-checker");
    try {
      final isMock = await platform.invokeMethod<bool>("isMockLocation");
      return isMock ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> initLocation() async {
    await Geolocator.requestPermission();
    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) async {
      currentPosition.value = pos;
      isMocked.value = await checkMockLocation(pos);
      if (isMocked.value) Get.snackbar("Warning", "Mock location detected!");

      final dist = Geolocator.distanceBetween(
        designatedLat,
        designatedLng,
        pos.latitude,
        pos.longitude,
      );

      currentDistance.value = dist;
      isWithinRadius.value = dist <= 1000;
    });
  }

  bool get canPunch {
    if (!isWithinRadius.value) return false;
    if (isMocked.value) return false;

    if (lastPunchTime != null) {
      final now = DateTime.now();
      if (now.difference(lastPunchTime!) < const Duration(seconds: 60))
        return false;
      if (now.year == lastPunchTime!.year &&
          now.month == lastPunchTime!.month &&
          now.day == lastPunchTime!.day) return false;
    }
    return true;
  }

  Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return "Unknown address";
      final p = placemarks.first;
      return "${p.street}, ${p.locality}, ${p.country}";
    } catch (_) {
      return "Address unavailable (Offline)";
    }
  }

  Future<void> loadRecentPunches() async {
    recentPunches.value = await DBHelper.instance.getPunchesForLast5Days();
  }

  Future<void> punchIn() async {
    final pos = currentPosition.value;
    if (pos == null) {
      Get.snackbar("Error", "Location not ready");
      return; // exit the function
    }

    if (!canPunch) {
      Get.snackbar(
        "Error",
        isMocked.value
            ? "Cannot punch using mock location"
            : "Punch not allowed",
      );
      return; // exit the function
    }

    isPunching.value = true;

    bool online = await hasInternet();
    String address = online
        ? await reverseGeocode(pos.latitude, pos.longitude)
        : "Offline — GPS only";

    final punch = Punch(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      latitude: pos.latitude,
      longitude: pos.longitude,
      address: address,
    );

    await DBHelper.instance.insertPunch(punch);

    lastPunchTime = DateTime.now();
    await loadRecentPunches();
    await loadLastNDaysGrouped(days: 5);

    isPunching.value = false;

    Get.snackbar(
        "Success", online ? "Punch recorded!" : "Punch saved offline!");
  }

  Future<void> loadLastNDaysGrouped({int days = 5}) async {
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));

    final punches = await DBHelper.instance.getPunchesSince(startDate);

    final Map<String, List<Punch>> map = {};
    for (int i = 0; i < days; i++) {
      final day = startDate.add(Duration(days: i));
      map[_dateKey(day)] = [];
    }

    for (final p in punches) {
      final dt = DateTime.fromMillisecondsSinceEpoch(p.timestamp);
      final key = _dateKey(dt);
      map[key] ??= [];
      map[key]!.add(p);
    }

    map.forEach(
        (key, list) => list.sort((a, b) => b.timestamp.compareTo(a.timestamp)));
    groupedPunches.value = map;
  }

  String _dateKey(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt);

/*
  Future<void> exportAndShareCSV() async {
    if (recentPunches.isEmpty) {
      Get.snackbar("Info", "No data available to export");
      return;
    }

    String csv = "Date,Time,Latitude,Longitude,Address\n";
    for (var p in recentPunches) {
      final dt = DateTime.fromMillisecondsSinceEpoch(p.timestamp);
      final date = DateFormat("yyyy-MM-dd").format(dt);
      final time = DateFormat("hh:mm a").format(dt);
      csv +=
          "$date,$time,${p.latitude},${p.longitude},\"${p.address.replaceAll(",", " ")}\"\n";
    }

    // Safe temp directory (always allowed)
    final dir = await getTemporaryDirectory();
    final file = File("${dir.path}/punch_history.csv");

    await file.writeAsString(csv);

    // ✅ Open Android share sheet (user chooses Downloads, Drive, etc.)
    await Share.shareXFiles(
      [XFile(file.path)],
      text: "Punch History CSV",
    );
  }
*/

// ------------------- Export & Share CSV -------------------

  Future<String> exportAndShareCSV() async {
    if (recentPunches.isEmpty) {
      Get.snackbar("Info", "No data available to export");
      return "";
    }

    // Create CSV content
    String csv = "Date,Time,Latitude,Longitude,Address\n";
    for (var p in recentPunches) {
      final dt = DateTime.fromMillisecondsSinceEpoch(p.timestamp);
      final date = DateFormat("yyyy-MM-dd").format(dt);
      final time = DateFormat("hh:mm a").format(dt);
      csv +=
          "$date,$time,${p.latitude},${p.longitude},\"${p.address.replaceAll(",", " ")}\"\n";
    }

    // Save directly into Downloads (NO PERMISSION REQUIRED)
    final filePath = await MediaStore.appFolder.saveFile(
      fileName: "punch_history.csv",
      content: csv.codeUnits,
      mimeType: "text/csv",
      dirType: DirType.download, // Saves in Downloads
    );

    Get.snackbar("Success", "CSV downloaded to Downloads Folder");

    return filePath ?? "";
  }
}
*/
