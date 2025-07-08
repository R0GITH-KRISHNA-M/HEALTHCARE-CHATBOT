import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:url_launcher/url_launcher.dart';
import 'auth_service.dart';

class MapScreen extends StatefulWidget {
  final User user;
  const MapScreen({super.key, required this.user});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  LatLng? _currentPosition;
  bool _isLoading = true;
  String? _error;
  bool _cameraMoved = false;
  List<Map<String, dynamic>> _hospitals = [];
  bool _loadingHospitals = false;
  Set<Marker> _hospitalMarkers = {};
  BitmapDescriptor? _hospitalIcon;
  Set<Polyline> _polylines = {};
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _createHospitalIcon();
    _initializeLocation();
  }

  Future<void> _createHospitalIcon() async {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'H',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final paint = Paint()..color = Colors.red;
    canvas.drawCircle(const Offset(24, 24), 24, paint);

    textPainter.paint(canvas, const Offset(12, 8));

    final picture = recorder.endRecording();
    final image = await picture.toImage(48, 48);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    setState(() {
      _hospitalIcon = BitmapDescriptor.fromBytes(bytes);
    });
  }

  Future<void> _initializeLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _error = 'Please enable location services';
        _isLoading = false;
      });
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _error = 'Location permissions are required';
          _isLoading = false;
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _error = 'Location permissions are permanently denied';
        _isLoading = false;
      });
      return;
    }

    await _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _isLoading = false;
      });

      if (_mapController != null) {
        _moveToCurrentLocation();
      }

      await _fetchNearbyHospitals();
    } catch (e) {
      setState(() {
        _error = 'Failed to get location: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchNearbyHospitals() async {
    if (_currentPosition == null) return;

    setState(() {
      _loadingHospitals = true;
      _hospitals.clear();
      _hospitalMarkers.clear();
      _polylines.clear();
    });

    try {
      final response = await http.get(Uri.parse(
          'https://maps.googleapis.com/maps/api/place/nearbysearch/json?'
              'location=${_currentPosition!.latitude},${_currentPosition!.longitude}'
              '&radius=1500'
              '&type=hospital'
              '&key=AIzaSyDdxaUFnUlhZPhzso-AqGUDQzQRS1tjYQE'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK') {
          final hospitals = (data['results'] as List).cast<Map<String, dynamic>>();

          final markers = <Marker>{
            if (_currentPosition != null)
              Marker(
                markerId: const MarkerId('current_location'),
                position: _currentPosition!,
                infoWindow: const InfoWindow(title: 'Your Location'),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
              ),
            ...hospitals.map((hospital) {
              final lat = hospital['geometry']['location']['lat'];
              final lng = hospital['geometry']['location']['lng'];
              return Marker(
                markerId: MarkerId(hospital['place_id']),
                position: LatLng(lat, lng),
                icon: _hospitalIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                infoWindow: InfoWindow(
                  title: hospital['name'],
                  snippet: hospital['vicinity'] ?? '',
                ),
              );
            }),
          };

          setState(() {
            _hospitals = hospitals;
            _hospitalMarkers = markers;
          });
        } else {
          throw Exception(data['error_message'] ?? 'Failed to load hospitals');
        }
      } else {
        throw Exception('Failed to load hospitals: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load hospitals: ${e.toString()}';
      });
    } finally {
      setState(() {
        _loadingHospitals = false;
      });
    }
  }

  void _moveToCurrentLocation() {
    if (_currentPosition != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_currentPosition!, 14),
      );
      setState(() {
        _cameraMoved = true;
      });
    }
  }

  void _zoomToHospital(LatLng position) {
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(position, 16),
    );
  }

  double _calculateDistance(double lat, double lng) {
    if (_currentPosition == null) return 0.0;
    return Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      lat,
      lng,
    ) / 1000;
  }

  Future<void> _showDirections(LatLng destination) async {
    if (_currentPosition == null) return;

    // Find the hospital corresponding to the destination
    final selectedHospital = _hospitals.firstWhere(
          (hospital) {
        final lat = hospital['geometry']['location']['lat'];
        final lng = hospital['geometry']['location']['lng'];
        return LatLng(lat, lng) == destination;
      },
      orElse: () => <String, dynamic>{},
    );

    if (selectedHospital.isNotEmpty) {
      // Save the selected hospital to Firestore
      await _authService.saveHospitalSearch(
        userId: widget.user.uid,
        hospital: selectedHospital,
        location: _currentPosition!,
      );
    }

    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
            '&origin=${_currentPosition!.latitude},${_currentPosition!.longitude}'
            '&destination=${destination.latitude},${destination.longitude}'
            '&travelmode=driving');

    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch Google Maps')),
      );
    }
  }

  Future<void> _drawRouteOnMap(LatLng destination) async {
    if (_currentPosition == null) return;

    final response = await http.get(Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?'
            'origin=${_currentPosition!.latitude},${_currentPosition!.longitude}'
            '&destination=${destination.latitude},${destination.longitude}'
            '&key=AIzaSyDdxaUFnUlhZPhzso-AqGUDQzQRS1tjYQE'));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['status'] == 'OK') {
        final points = data['routes'][0]['overview_polyline']['points'];
        List<LatLng> routeCoords = _decodePoly(points);

        setState(() {
          _polylines.clear();
          _polylines.add(Polyline(
            polylineId: const PolylineId('route'),
            points: routeCoords,
            color: Colors.blue,
            width: 5,
          ));
        });
      }
    }
  }

  List<LatLng> _decodePoly(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      poly.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return poly;
  }

  Widget _buildMap() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _error!,
              style: const TextStyle(fontSize: 16, color: Colors.red),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _initializeLocation,
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    return GoogleMap(
      onMapCreated: (controller) {
        _mapController = controller;
        if (!_cameraMoved) {
          _moveToCurrentLocation();
        }
      },
      initialCameraPosition: CameraPosition(
        target: _currentPosition ?? const LatLng(0, 0),
        zoom: 14,
      ),
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      markers: _hospitalMarkers,
      polylines: _polylines,
    );
  }

  Widget _buildHospitalList() {
    if (_loadingHospitals) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_hospitals.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No hospitals found nearby'),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8.0),
      itemCount: _hospitals.length,
      itemBuilder: (context, index) {
        final hospital = _hospitals[index];
        final lat = hospital['geometry']['location']['lat'];
        final lng = hospital['geometry']['location']['lng'];
        final distance = _calculateDistance(lat, lng);
        final destination = LatLng(lat, lng);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
          elevation: 2.0,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.local_hospital, color: Colors.red, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        hospital['name'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 44.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hospital['vicinity'] ?? '',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (hospital['rating'] != null) ...[
                            const Icon(Icons.star, color: Colors.amber, size: 18),
                            const SizedBox(width: 4),
                            Text(
                              hospital['rating'].toStringAsFixed(1),
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(width: 16),
                          ],
                          const Icon(Icons.directions_walk, color: Colors.blue, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            '${distance.toStringAsFixed(1)} km',
                            style: TextStyle(
                                color: Colors.blue[700], fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.directions, size: 18),
                          label: const Text('Directions'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => _showDirections(destination),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Hospitals'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchNearbyHospitals,
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: () {
              if (_currentPosition != null) {
                _moveToCurrentLocation();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: _buildMap(),
          ),
          Expanded(
            child: _buildHospitalList(),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}