import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../facilities/domain/facility.dart';

sealed class LocationResult {
  const LocationResult();
}

class LocationFound extends LocationResult {
  const LocationFound(this.point, this.accuracyMeters);
  final GeoPoint point;
  final double accuracyMeters;

  /// Precisão baixa: comunicar e oferecer ajuste manual.
  bool get isImprecise => accuracyMeters > 100;
}

class LocationPermissionDenied extends LocationResult {
  const LocationPermissionDenied({required this.permanently});
  final bool permanently;
}

class LocationServiceDisabled extends LocationResult {
  const LocationServiceDisabled();
}

class LocationUnavailable extends LocationResult {
  const LocationUnavailable(this.detail);
  final String detail;
}

/// Localização em primeiro plano, pedida somente por ação do usuário.
/// A coordenada fica apenas em memória; não é gravada nem enviada.
class LocationService {
  const LocationService();

  Future<LocationResult> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationServiceDisabled();
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      switch (permission) {
        case LocationPermission.denied:
          return const LocationPermissionDenied(permanently: false);
        case LocationPermission.deniedForever:
          return const LocationPermissionDenied(permanently: true);
        case LocationPermission.unableToDetermine:
          return const LocationUnavailable('permissão indeterminada');
        case LocationPermission.whileInUse:
        case LocationPermission.always:
          break;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 30),
        ),
      );
      return LocationFound(
        GeoPoint(position.latitude, position.longitude),
        position.accuracy,
      );
    } on TimeoutException {
      return const LocationUnavailable(
        'O GPS não respondeu a tempo. Tente em área aberta ou escolha no mapa.',
      );
    } on LocationServiceDisabledException {
      return const LocationServiceDisabled();
    } on PermissionDefinitionsNotFoundException {
      return const LocationUnavailable('permissões ausentes no aplicativo');
    } on Exception catch (e) {
      return LocationUnavailable(e.toString());
    }
  }

  Future<bool> openAppSettings() => Geolocator.openAppSettings();
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}
