import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; //allows digit-only input
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:async';

import 'src/weather_service.dart';

//suggested by GCP to put here
enum PositionSource { current, lastKnown }

class PositionWithSource {
  final Position position;
  final PositionSource source;

  PositionWithSource(this.position, this.source);
}
//END: GCP's suggestion.

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final TextEditingController _zipController = TextEditingController();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();//GCP

  @override
  void dispose() {
    _zipController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit(BuildContext context) async {
    final String raw = _zipController.text;
    final String zip = raw.trim();

    // Basic validation: must be 5 digits
    if (zip.length != 5 || int.tryParse(zip) == null) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Please enter a valid 5-digit ZIP code.')),
      );
      return;
    }

    // Resolve ZIP -> Location (await the Future and handle null)
    final Location? place = await locationFromZip(zip);
    if (place == null) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Could not resolve ZIP to coordinates.')),
      );
      return;
    }

    final double lat = place.latitude;
    final double lon = place.longitude;

    // Optionally resolve a city/place name (best-effort)
    String? placeName;
    try {
      final List<Placemark> placemarks = await placemarkFromCoordinates(lat, lon);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        placeName = p.locality ?? p.subAdministrativeArea ?? p.administrativeArea;
      }
    } catch (e) {
      debugPrint('place name lookup failed: $e');
      placeName = null;
    }

    if (!mounted) return;

    // Navigate to the WeatherService page with concrete (non-null) values
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WeatherService(
          lat: lat,
          lon: lon,
          zip: zip,
          cityName: placeName,
        ),
      ),
    );
  }

  //Helper function for converting a ZIP code to lat and lon.
  Future<Location?> locationFromZip(String zip) async {
    try {
      final places = await locationFromAddress(zip);
      if (places.isEmpty) return null;
      return places.first; // has latitude & longitude fields
    } catch (e) {
      debugPrint('locationFromAddress failed: $e');
      return null;
    }    
  }
  // Helper: return a single Position (current if available, otherwise last-known)
  Future<Position?> _checkLocationService() async {
    //permission stuff
    bool serviceEnabled;
    LocationPermission permission;
    // test if location service is enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // perms denied, next time can try requesting perms again
        return Future.error('Location permissions are denied');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      // perms denied forever, handle appropriately
      return Future.error(
          'Location permissions are currently denied, we cannot request permissions. If you would like to enable permissions, please go to your Settings and then Enable Location Service for this app.');
    }
    //permissions END
    // Trying to access current position, or last known if otherwise cannot collect.
    final Position? lastKnown = await Geolocator.getLastKnownPosition();
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 10));
      return pos; // current position obtained
    } catch (e) {
      // couldn't get current; fall back to last-known
      debugPrint('getCurrentPosition failed: $e — trying lastKnown');
      if (lastKnown != null) return lastKnown;
      // nothing available
      return null;
    }
  }


  Future<String?> reverseGeocodePostalFromPosition(Position pos, {Duration timeout = const Duration(seconds:10)}) async {
    try {
      final double lat = pos.latitude;
      final double lon = pos.longitude;

      final List<Placemark> placemarks = await placemarkFromCoordinates(lat, lon).timeout(timeout);
      if (placemarks.isEmpty) return null;

      // final Placemark p = placemarks.first;
      final String? postal = placemarks.first.postalCode;
      if (postal == null || postal.trim().isEmpty) return null;
      return postal.trim();
    } on TimeoutException {
      // timed out
      return null;
    } catch (e) {
      // log for debugging
      debugPrint('reverseGeocode error: $e');
      return null;
    }
  }

  

  Future<void> _getZIP() async {//would like help on understanding this later, probably
    try {
      final Position? pos = await _checkLocationService();
      if (pos == null) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Location not available.')),
        );
        return;
      }

      if (!mounted) return;

      // We have a Position object; reverse-geocode it
      _scaffoldMessengerKey.currentState?.showSnackBar(const SnackBar(content: Text('Resolving postal code...')));
      final String? postal = await reverseGeocodePostalFromPosition(pos);

      if (!mounted) return;

      if (postal != null) {
        _zipController.text = postal;
        _scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(content: Text('Found ZIP: $postal')));
      } else {
        // Fallback: lat/lon placeholder
        _zipController.text = '${pos.latitude.toStringAsFixed(5)},${pos.longitude.toStringAsFixed(5)}';
        _scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Postal code not available for this location.')),
        );
      }
    } catch (e) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Location error: $e')),
      );
      return;
    }

  }
  //So does _checkLocationService become the variable to use when referring to the data returned by Geolocator.getCurrentPosition?

    //get permission from user to get lat and lon info, store said info
    //convert info to ZIP, location names, etc.
    //input zip into text area.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _scaffoldMessengerKey,//wat dis. So far, only did step 2.
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Weather App'),
          backgroundColor: Colors.lightBlue,
        ),
        drawer: Drawer(
          child: Container(
            color: Colors.lightBlue[300],
            child: const Padding(
              padding: EdgeInsets.only(top: 50, left: 16),
              child: Text('Drawer'),
            ),
          ),
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'Welcome to the Weather App',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Please enter your ZIP code to get started',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.normal),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 250, // total width for TextField + Button
                  child: Row(
                    //Enter ZIP and accompanying Submit Button
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _zipController,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number, //numbers only
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(5),
                          ],
                          decoration: const InputDecoration(
                            hintText: '90210',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8), // spacing
                      IconButton(
                        onPressed: _getZIP,
                        icon: const Icon(Icons.my_location),
                        tooltip: 'Geolocate ZIP',
                        splashRadius: 20,
                        color: Colors.blue[800],
                        //todo? Make a border
                      ),
                      const SizedBox(width: 8), // spacing
                      Builder(
                        builder: (innerContext) => ElevatedButton(
                          onPressed: () => _handleSubmit(innerContext),
                          child: const Text('Search'),
                        ),
                      ),
                    ],
                  ),
                ),
                // ScaffoldMessenger.of(context)
                
              ],
            ),
          ),
        ),
      ),
    );
  }
}
