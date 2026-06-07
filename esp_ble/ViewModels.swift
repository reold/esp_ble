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
        
        // 1. Request "Always" authorization to allow tracking when screen is locked/app minimised
        locationManager.requestAlwaysAuthorization()
        
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        // 2. Set distance filter to avoid spamming the ESP32 when standing still (e.g. 5 meters)
        locationManager.distanceFilter = 5.0
        
        // 3. ESSENTIAL: Tell iOS this app must receive locations in the background explicitly
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.pausesLocationUpdatesAutomatically = false
        
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
    
    // 4. Triggered automatically by iOS (even in the background) when location changes
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        let coordinate = location.coordinate
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let timestamp = formatter.string(from: location.timestamp)
        
        // Update the published property, which triggers the reactive sink in BluetoothViewModel
        let payload = "GPS:\(coordinate.latitude),\(coordinate.longitude),ts=\(timestamp)"
        latestText = payload
    }
    
    // Retained for manual sending if necessary
    func currentPayload() -> String {
        return latestText
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
    
    private var scanTimer: Timer?
    // Note: sendTimer removed completely — timers don't run in iOS background.
    
    private let locationManager = LocationManager()
    private var locationSubscription: AnyCancellable?
    
    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        
        // 5. Instantly react to background location updates coming from LocationManager
        locationSubscription = locationManager.$latestText.sink { [weak self] text in
            self?.dataTransfer.locationText = text
            
            // If connected, automatically push the location to ESP32!
            // iOS gives us brief execution time here even when the screen is locked.
            if self?.connectionState == .connected {
                self?.sendData(text)
            }
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
        // Prevent sending "Waiting for location..." to ESP32 before hardware syncs
        if !payload.starts(with: "Waiting") && !payload.starts(with: "LOC:pending") {
            sendData(payload)
        }
    }
    
    private func resetConnection() {
        connectionState = .disconnected
        status = connectionState.statusText
        writeCharacteristic = nil
        peripheral = nil
        deviceInfo = DeviceInfo()
        deviceInfo.writeWithoutResponse = false
    }
    
    private func sendData(_ string: String) {
        guard let peripheral = peripheral, let characteristic = writeCharacteristic else {
            return
        }
        
        let data = Data(string.utf8)
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        
        peripheral.writeValue(data, for: characteristic, type: writeType)
        
        deviceInfo.writeWithoutResponse = (writeType == .withoutResponse)
        deviceInfo.mtuBytes = peripheral.maximumWriteValueLength(for: writeType)
        
        // Ensure UI updates aren't conflicting
        DispatchQueue.main.async { [weak self] in
            self?.dataTransfer.lastSent = string
            self?.dataTransfer.lastSentBytes = data.count
            self?.dataTransfer.totalSentBytes += data.count
        }
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
            
            // We no longer need the timer; just send an immediate payload to get it started
            sendLocation()
        } else {
            status = "Characteristic not found"
        }
    }
}