import 'dart:async';
import 'dart:developer';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:uuid/uuid.dart';

final uid = Uuid().v4();

class CommunityWidget extends StatefulWidget {

  @override
  State<CommunityWidget> createState() {
    return _CommunityState();
  }

}

class _CommunityState extends State<CommunityWidget> {
  late Timer _timer;
  late Location _location;
  late StreamSubscription _locationSubscription;
  Map<String, Marker> _markers = Map();
  bool _locationNotAvail = false;
  bool _locationNotAvailAlerted = false;
  late GoogleMapController _controller;

  // This variable should be set to
  // - http://localhost:8080 : for iOS Simulator
  // - http://10.0.2.2:8080  : for Android Emulator
  // - whatever host and port you are running the globoscript-server on for a physical device
  String baseUrl = "http://10.0.2.2:8080";


  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(Duration(seconds: 5), timerUpdate);

    _location = new Location();

    /*
     * In the demo, for simplicity, the _locationSetup method has been merged with initState,
     * making initState async. This is not possible, because initState cannot be async, so in
     * the actual demo code here, we have moved the location setup with the asynchronous
     * calls into a separate method - this is standard practice.
     */
    _locationSetup();
  }

  void _locationSetup() async {

    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        _locationNotAvail = true;
        return;
      }
    }

    PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        _locationNotAvail = true;
        return;
      }
    }

    _locationSubscription = _location.onLocationChanged.listen((LocationData currentLocation) async {
      double lat = currentLocation.latitude!;
      double lng = currentLocation.longitude!;
      _controller.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
      setState(() {
        MarkerId id = MarkerId("MyLocation");
        _markers["MyLocation"] = Marker(markerId: id, position: LatLng(lat, lng));
      });
      final response = await http.put(Uri.parse(baseUrl + '/userLocation'),
          body: '{"username": "$uid", "longitude": $lng, "latitude": $lat}',
          headers: {"Content-Type": "application/json"}
      );
      if (response.statusCode != 200) {
        log('Unable to update user location on the REST API server');
      }
    });

  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      mapType: MapType.normal,
      initialCameraPosition: CameraPosition(
        target: LatLng(35.6908, 139.7077),
        zoom: 14.4746,
      ),
      markers: Set<Marker>.of(_markers.values),
      onMapCreated: (GoogleMapController controller) {
        _controller = controller;
      },
    );
  }

  @override
  void dispose() {
    // remember to cancel the subscription when done
    _locationSubscription.cancel();
    // remember to cancel the timer when done
    _timer.cancel();
    // delete the user session from the backend
    http.delete(Uri.parse(baseUrl + '/userLocation/$uid'));
    // remember to dispose of the map when done
    _controller.dispose();
    super.dispose();
  }

  void timerUpdate(Timer _) async {

    // (1) Tell users that location is not available, but only the first time
    if (_locationNotAvail) {
      if (!_locationNotAvailAlerted) {
        _locationNotAvailAlerted = true;
        showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text("Location Services"),
                // To display the title it is optional
                content: Text("Location Services are not enabled or permission has not been granted"),
                // Message which will be pop up on the screen
                // Action widget which will provide the user to acknowledge the choice
                actions: [
                  TextButton(
                    onPressed: () { Navigator.pop(context); },
                    child: Text('Ok', style: TextStyle(color: Colors.black)),
                  ),
                ],
              );
            }
        );
      }
      return;
    }

    // (2) Get the user locations from the backend service
    final response = await http.get(Uri.parse(baseUrl + '/userLocation'));
    if (response.statusCode == 200) {
      List<dynamic> json = jsonDecode(response.body);
      for (var map in json) {
        var username = map["username"];
        if (username != null && username != uid.toString()) {
          // Create markers from the JSON response
          MarkerId id = MarkerId(username);
          _markers[username] = Marker(markerId: id, position: LatLng(map["latitude"], map["longitude"]));
        }
      }
      log("User locations: $_markers");
    } else {
      log('Unable to fetch user locations from the REST API server');
    }
    setState(() {});

  }

}