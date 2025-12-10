import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

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

  Future<String> exportAndShareCSV() async {
    if (recentPunches.isEmpty) {
      Get.snackbar("Info", "No data available to export");
      return "";
    }

    String csv = "Date,Time,Latitude,Longitude,Address\n";
    for (var p in recentPunches) {
      final dt = DateTime.fromMillisecondsSinceEpoch(p.timestamp);
      final date = DateFormat("yyyy-MM-dd").format(dt);
      final time = DateFormat("hh:mm a").format(dt);
      csv +=
          "$date,$time,${p.latitude},${p.longitude},\"${p.address.replaceAll(",", " ")}\"\n";
    }

    // ✅ Convert to bytes
    Uint8List bytes = Uint8List.fromList(csv.codeUnits);

    String? path = await FileSaver.instance.saveFile(
      name: "punch_history",
      bytes: bytes,
      mimeType: MimeType.csv,
    );

    if (path != null) {
      Get.snackbar("Success", "File saved successfully");
      return path;
    } else {
      Get.snackbar("Error", "File save cancelled");
      return "";
    }
  }
}
