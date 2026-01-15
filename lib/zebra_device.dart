import 'dart:convert';

import 'package:flutter/services.dart';

/// Enum representing normalized printer statuses irrespective of platform/localization
enum ZebraStatus {
  connected,
  disconnected,
  connecting,
  disconnecting,
  sendingData,
  done,
  portInvalid,
  unknown,
}

/// Attempts to parse a status label (possibly localized) and optional color/isConnected hints
/// into a ZebraStatus value.
ZebraStatus zebraStatusFromStrings(String? status,
    {String? color, bool? isConnected}) {
  final s = (status ?? '').trim().toLowerCase();

  // Quick disambiguation using known keywords (English + common Spanish variants)
  if (s.contains('port invalid')) return ZebraStatus.portInvalid;
  if (s.contains('sending')) return ZebraStatus.sendingData; // Sending Data
  if (s.contains('enviando')) return ZebraStatus.sendingData; // Enviando información
  if (s.contains('disconnecting') || s.contains('desconectando')) {
    return ZebraStatus.disconnecting;
  }
  if (s.contains('connecting') || s.contains('conectando')) {
    return ZebraStatus.connecting;
  }
  if (s.contains('connected') || s.contains('conectado')) {
    return ZebraStatus.connected;
  }
  if (s.contains('disconnected') || s.contains('desconectado')) {
    return ZebraStatus.disconnected;
  }
  if (s.contains('done') || s.contains('completado')) return ZebraStatus.done;

  // Use color as a heuristic fallback when label is localized/unknown
  switch ((color ?? '').toUpperCase()) {
    case 'G':
      // Green usually means connected/done; prefer connected unless explicitly done
      return ZebraStatus.connected;
    case 'R':
      return ZebraStatus.disconnected;
    case 'Y':
      // Yellow typically used for connecting/sending; default to connecting
      return ZebraStatus.connecting;
  }

  // Fallback to isConnected hint if provided
  if (isConnected == true) return ZebraStatus.connected;

  return ZebraStatus.unknown;
}

List<ZebraDevice> zebraDevicesModelFromJson(String str) =>
    List<ZebraDevice>.from(
        json.decode(str).map((x) => ZebraDevice.fromJson(x)));

String zebraDevicesToJson(List<ZebraDevice> data) =>
    json.encode(List<dynamic>.from(data.map((x) => x.toJson())));

ZebraDevice zebraDeviceModelFromJson(String str) =>
    ZebraDevice.fromJson(jsonDecode(str));

class ZebraDevice {
  final String address;
  final String name;
  final String status;
  final ZebraStatus statusEnum;
  final bool isWifi;
  final Color color;
  final bool isConnected;

  ZebraDevice(
      {required this.address,
      required this.name,
      required this.isWifi,
      required this.status,
      required this.statusEnum,
      this.isConnected = false,
      this.color = const Color.fromARGB(255, 255, 0, 0),
      });
      
  factory ZebraDevice.empty() =>
      ZebraDevice(address: "", name: "", isWifi: false, status: '', statusEnum: ZebraStatus.unknown);

  factory ZebraDevice.fromJson(Map<String, dynamic> json) => ZebraDevice(
      address: json["ipAddress"] ?? json["macAddress"],
      name: json["name"],
      isWifi: json["isWifi"].toString() == "true",
      isConnected: json["isConnected"],
      status: json["status"] ,
      statusEnum: json.containsKey('statusEnum')
          ? _parseStatusEnum(json['statusEnum'])
          : zebraStatusFromStrings(json["status"],
              color: _tryParseColorKey(json['color']),
              isConnected: json['isConnected'] == true),
      color: json["color"]);

  Map<String, dynamic> toJson() => {
        "ipAddress": address,
        "name": name,
        "isWifi": isWifi,
        "status": status,
        "statusEnum": statusEnum.name,
        "isConnected": isConnected,
        "color": color
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ZebraDevice && other.address == address;
  }

  @override
  int get hashCode => address.hashCode;

  ZebraDevice copyWith(
      {String? ipAddress,
      String? name,
      bool? isWifi,
      String? status,
      ZebraStatus? statusEnum,
      bool? isConnected,
      Color? color}) {
    return ZebraDevice(
        address: ipAddress ?? this.address,
        name: name ?? this.name,
        isWifi: isWifi ?? this.isWifi,
        status: status ?? this.status,
        statusEnum: statusEnum ?? this.statusEnum,
        isConnected: isConnected ?? this.isConnected,
        color: color ?? this.color);
  }
}

ZebraStatus _parseStatusEnum(dynamic val) {
  if (val is ZebraStatus) return val;
  final s = val?.toString().toLowerCase();
  switch (s) {
    case 'connected':
      return ZebraStatus.connected;
    case 'disconnected':
      return ZebraStatus.disconnected;
    case 'connecting':
      return ZebraStatus.connecting;
    case 'disconnecting':
      return ZebraStatus.disconnecting;
    case 'sendingdata':
    case 'sending_data':
      return ZebraStatus.sendingData;
    case 'done':
      return ZebraStatus.done;
    case 'portinvalid':
    case 'port_invalid':
      return ZebraStatus.portInvalid;
    default:
      return ZebraStatus.unknown;
  }
}

String? _tryParseColorKey(dynamic color) {
  if (color == null) return null;
  // Accept either a simple color code like 'R'/'G'/'Y' or a Flutter Color; only code helps here
  if (color is String) return color;
  return null;
}
