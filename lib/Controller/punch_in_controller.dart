import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
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
  var isExporting = false.obs;

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
      if (isMocked.value) {
        Get.snackbar("Warning", "Mock location detected!");
      }

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

  // ⭐ UPDATED: Only 5-minute restriction. Same-day allowed.
  bool get canPunch {
    if (!isWithinRadius.value) return false;
    if (isMocked.value) return false;

    if (lastPunchTime != null) {
      final now = DateTime.now();

      // Only 5-minute lock
      if (now.difference(lastPunchTime!) < const Duration(minutes: 5)) {
        return false;
      }
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
      return;
    }

    final now = DateTime.now();

    // 🚫 Not within 1 KM
    if (!isWithinRadius.value) {
      Get.snackbar(
        "Error",
        "You are outside the allowed 1 KM radius!",
      );
      return;
    }

    // 🚫 Mock location check
    if (isMocked.value) {
      Get.snackbar("Error", "Mock location detected!");
      return;
    }

    // 🚫 5-Minute cooldown check
    if (lastPunchTime != null) {
      final diff = now.difference(lastPunchTime!);
      if (diff < const Duration(minutes: 5)) {
        final remaining = const Duration(minutes: 5) - diff;

        Get.snackbar(
          "Please Wait",
          "You can punch again in ${remaining.inMinutes} min "
              "${remaining.inSeconds % 60} sec",
        );
        return;
      }
    }

    // ⭐ Passed all checks — Punch can happen
    isPunching.value = true;

    bool online = await hasInternet();
    String address = online
        ? await reverseGeocode(pos.latitude, pos.longitude)
        : "Offline — GPS only";

    final punch = Punch(
      timestamp: now.millisecondsSinceEpoch,
      latitude: pos.latitude,
      longitude: pos.longitude,
      address: address,
    );

    await DBHelper.instance.insertPunch(punch);

    lastPunchTime = now;

    await loadRecentPunches();
    await loadLastNDaysGrouped(days: 5);

    isPunching.value = false;

    Get.snackbar(
      "Success",
      online ? "Punch recorded!" : "Punch saved offline!",
    );
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

  Future<void> downloadCSV() async {
    if (recentPunches.isEmpty) {
      Get.snackbar(
        "Info",
        "No punch data available to export",
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    try {
      isExporting.value = true;

      String csv = "Date,Time,Latitude,Longitude,Address\n";

      for (var p in recentPunches) {
        final dt = DateTime.fromMillisecondsSinceEpoch(p.timestamp);
        final date = DateFormat("yyyy-MM-dd").format(dt);
        final time = DateFormat("hh:mm a").format(dt);

        final cleanAddress = p.address.replaceAll('"', '""');

        csv += '$date,$time,${p.latitude},${p.longitude},"$cleanAddress"\n';
      }

      Directory? directory;

      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');

        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else if (Platform.isIOS) {
        directory = await getApplicationDocumentsDirectory();
      }

      if (directory == null) {
        throw Exception("Unable to access storage directory");
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = "punch_history_$timestamp.csv";
      final filePath = "${directory.path}/$fileName";

      final file = File(filePath);
      await file.writeAsString(csv);

      isExporting.value = false;

      Get.snackbar(
        "✅ Success",
        "CSV saved: $fileName",
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 5),
        mainButton: TextButton(
          onPressed: () => OpenFile.open(filePath),
          child: const Text(
            "OPEN",
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    } catch (e) {
      isExporting.value = false;
      Get.snackbar(
        "Error",
        "Failed to export CSV: ${e.toString()}",
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      return status.isGranted;
    }
    return true;
  }

  Future<void> downloadCSVWithPermission() async {
    if (recentPunches.isEmpty) {
      Get.snackbar(
        "Info",
        "No punch data available to export",
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final hasPermission = await _requestStoragePermission();
    if (!hasPermission) {
      Get.snackbar(
        "Permission Required",
        "Storage permission needed to save CSV",
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    await downloadCSV();
  }
}
