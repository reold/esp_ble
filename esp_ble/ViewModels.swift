import SwiftUI
import CoreBluetooth
import CoreLocation
import Combine

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var latestText: String = "Waiting for location..."
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
        default:
            latestText = "Location permission denied"
        }
    }
    
    func currentPayload() -> String {
        guard let location = locationManager.location else { return "LOC:pending" }
        let coordinate = location.coordinate
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let timestamp = formatter.string(from: location.timestamp)
        let payload = "GPS:\(coordinate.latitude),\(coordinate.longitude),ts=\(timestamp)"
        latestText = payload
        return payload
    }
}

final class BluetoothViewModel: NSObject, ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var status = "Initializing..."
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var showDeviceList = false
    @Published var textToSend = "hello world!"
    @Published var lastError: String? = nil
    @Published var deviceInfo = DeviceInfo()
    @Published var dataTransfer = DataTransferInfo()
    
    // Core Bluetooth
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    
    private var sendTimer: Timer?
    private var scanTimer: Timer?
    
    private let locationManager = LocationManager()
    private var locationSubscription: AnyCancellable?
    
    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        locationSubscription = locationManager.$latestText.sink { [weak self] text in
            self?.dataTransfer.locationText = text
        }
    }
    
    func scanForDevices() {
        guard central.state == .poweredOn else {
            status = "Bluetooth not ready"
            return
        }
        
        discoveredDevices.removeAll()
        connectionState = .scanning
        showDeviceList = true
        status = connectionState.statusText
        
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            self?.stopScanning()
        }
    }
    
    func stopScanning() {
        central.stopScan()
        scanTimer?.invalidate()
        scanTimer = nil
        if connectionState == .scanning {
            connectionState = .disconnected
            status = connectionState.statusText
        }
    }
    
    func connectToDevice(_ device: DiscoveredDevice) {
        showDeviceList = false
        connectionState = .connecting
        status = "Connecting to \(device.displayName)..."
        deviceInfo.name = device.displayName
        deviceInfo.uuid = device.peripheral.identifier.uuidString
        deviceInfo.rssi = device.rssi
        peripheral = device.peripheral
        stopScanning()
        device.peripheral.delegate = self
        central.connect(device.peripheral, options: nil)
    }
    
    func disconnect() {
        sendTimer?.invalidate()
        sendTimer = nil
        if let peripheral = peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        resetConnection()
    }
    
    func sendText() {
        sendData("TEXT:" + textToSend)
    }
    
    func sendLocation() {
        let payload = locationManager.currentPayload()
        sendData(payload)
    }
    
    private func resetConnection() {
        connectionState = .disconnected
        status = connectionState.statusText
        writeCharacteristic = nil
        peripheral = nil
        deviceInfo = DeviceInfo()
        deviceInfo.writeWithoutResponse = false
    }
    
    private func startSendingLoop() {
        sendTimer?.invalidate()
        sendTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.sendLocation()
        }
        sendLocation()
    }
    
    private func sendData(_ string: String) {
        guard let peripheral = peripheral, let characteristic = writeCharacteristic else {
            status = "Not connected"
            return
        }
        
        let data = Data(string.utf8)
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        
        peripheral.writeValue(data, for: characteristic, type: writeType)
        
        deviceInfo.writeWithoutResponse = (writeType == .withoutResponse)
        deviceInfo.mtuBytes = peripheral.maximumWriteValueLength(for: writeType)
        
        dataTransfer.lastSent = string
        dataTransfer.lastSentBytes = data.count
        dataTransfer.totalSentBytes += data.count
        
        status = "Connected"
    }
}

extension BluetoothViewModel: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        status = {
            switch central.state {
            case .poweredOn: return "Ready"
            case .poweredOff: return "Bluetooth OFF"
            case .unauthorized: return "Unauthorized"
            case .unsupported: return "Unsupported"
            case .resetting: return "Resetting"
            case .unknown: fallthrough
            @unknown default: return "Unknown"
            }
        }()
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        
        if !discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
            let device = DiscoveredDevice(
                peripheral: peripheral,
                name: name,
                rssi: RSSI.intValue,
                advertisementData: advertisementData
            )
            
            discoveredDevices.append(device)
            discoveredDevices.sort { $0.rssi > $1.rssi }
            if discoveredDevices.count > 10 {
                discoveredDevices = Array(discoveredDevices.prefix(10))
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connected
        status = "Discovering services..."
        peripheral.discoverServices([BLEConfiguration.targetServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        resetConnection()
        if let error = error {
            lastError = error.localizedDescription
        }
    }
}

extension BluetoothViewModel: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            status = "Service discovery failed"
            lastError = error.localizedDescription
            return
        }
        
        guard let service = peripheral.services?.first(where: { $0.uuid == BLEConfiguration.targetServiceUUID }) else {
            status = "Service not found"
            return
        }
        
        status = "Discovering characteristics..."
        peripheral.discoverCharacteristics([BLEConfiguration.targetCharacteristicUUID], for: service)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            status = "Characteristic discovery failed"
            lastError = error.localizedDescription
            return
        }
        
        writeCharacteristic = service.characteristics?.first(where: { $0.uuid == BLEConfiguration.targetCharacteristicUUID })
        
        if let characteristic = writeCharacteristic {
            deviceInfo.writeWithoutResponse = characteristic.properties.contains(.writeWithoutResponse)
            deviceInfo.mtuBytes = peripheral.maximumWriteValueLength(for: deviceInfo.writeWithoutResponse ? .withoutResponse : .withResponse)
            connectionState = .connected
            status = connectionState.statusText
            startSendingLoop()
        } else {
            status = "Characteristic not found"
        }
    }
}
