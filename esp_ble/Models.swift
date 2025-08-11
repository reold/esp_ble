import Foundation
import CoreBluetooth

struct BLEConfiguration {
    static let targetServiceUUID = CBUUID(string: "0000FFFF-0000-1000-8000-00805F9B34FB")
    static let targetCharacteristicUUID = CBUUID(string: "0000FF01-0000-1000-8000-00805F9B34FB")
}

struct DiscoveredDevice: Identifiable {
    let id = UUID()
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
    let advertisementData: [String: Any]
    
    var displayName: String {
        return name.isEmpty ? "Unknown Device" : name
    }
}

enum ConnectionState {
    case disconnected
    case scanning
    case connecting
    case connected
    
    var statusText: String {
        switch self {
        case .disconnected:
            return "Ready"
        case .scanning:
            return "Scanning for devices..."
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        }
    }
}

struct DeviceInfo {
    var name: String = "—"
    var uuid: String = "—"
    var rssi: Int?
    var mtuBytes: Int?
    var writeWithoutResponse: Bool = false
}

struct DataTransferInfo {
    var lastSent: String = "—"
    var lastSentBytes: Int = 0
    var totalSentBytes: Int = 0
    var locationText: String = "—"
}
