import SwiftUI

// MARK: - device list
struct DeviceListView: View {
    @ObservedObject var viewModel: BluetoothViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                if viewModel.connectionState == .scanning {
                    ScanningView(deviceCount: viewModel.discoveredDevices.count)
                }
                
                DevicesList(devices: viewModel.discoveredDevices) { device in
                    viewModel.connectToDevice(device)
                    dismiss()
                }
                
                if viewModel.connectionState != .scanning && viewModel.discoveredDevices.isEmpty {
                    EmptyDevicesView {
                        viewModel.scanForDevices()
                    }
                }
            }
            .navigationTitle("Bluetooth Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        viewModel.stopScanning()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        viewModel.scanForDevices()
                    }
                    .disabled(viewModel.connectionState == .scanning)
                }
            }
        }
    }
}

// MARK: - main view
struct ContentView: View {
    @StateObject private var viewModel = BluetoothViewModel()
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ConnectionStatusView(
                        status: viewModel.status,
                        isConnected: viewModel.connectionState == .connected
                    )
                    
                    if viewModel.deviceInfo.name != "—" {
                        DeviceInfoView(deviceInfo: viewModel.deviceInfo)
                    }
                    
                    if viewModel.connectionState == .connected {
                        ConnectionDetailsView(deviceInfo: viewModel.deviceInfo, dataTransfer: viewModel.dataTransfer)
                    }
                    
                    DataStreamView(dataTransfer: viewModel.dataTransfer)
                    
                    if let error = viewModel.lastError {
                        ErrorView(error: error)
                    }
                    
                    ControlsView(
                        viewModel: viewModel,
                        isTextFieldFocused: $isTextFieldFocused,
                        isConnected: viewModel.connectionState == .connected
                    )
                }
            }
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            ConnectButton(viewModel: viewModel)
        }
        .preferredColorScheme(.light)
        .sheet(isPresented: $viewModel.showDeviceList) {
            DeviceListView(viewModel: viewModel)
        }
    }
}

// MARK: - sub views
struct ScanningView: View {
    let deviceCount: Int
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Scanning for devices...")
            Text("Found \(deviceCount) devices")
        }
        .padding()
    }
}

struct DevicesList: View {
    let devices: [DiscoveredDevice]
    let onTap: (DiscoveredDevice) -> Void
    
    var body: some View {
        List(devices) { device in
            DeviceRow(device: device)
                .contentShape(Rectangle())
                .onTapGesture {
                    onTap(device)
                }
        }
    }
}

struct DeviceRow: View {
    let device: DiscoveredDevice
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(device.displayName)
                    .font(.headline)
                Spacer()
                Text("\(device.rssi) dBm")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(device.peripheral.identifier.uuidString)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct EmptyDevicesView: View {
    let onScanAgain: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("No devices found")
                .foregroundColor(.secondary)
            Button("Scan Again", action: onScanAgain)
        }
        .padding()
    }
}

struct StatusIndicator: View {
    let isConnected: Bool
    
    var body: some View {
        Circle()
            .fill(isConnected ? Color.green : Color.gray.opacity(0.3))
            .frame(width: 8, height: 8)
    }
}

struct ConnectionStatusView: View {
    let status: String
    let isConnected: Bool
    
    var body: some View {
        HStack {
            StatusIndicator(isConnected: isConnected)
            Text(status)
                .font(.system(size: 15, weight: .medium))
            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.top, 16)
    }
}

struct DeviceInfoView: View {
    let deviceInfo: DeviceInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Device")
            VStack(alignment: .leading, spacing: 0) {
                InfoRow("Name", deviceInfo.name)
                InfoRow("UUID", String(deviceInfo.uuid.prefix(8)) + "...")
                if let rssi = deviceInfo.rssi {
                    InfoRow("Signal", "\(rssi) dBm")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
        .padding(.horizontal)
    }
}

struct ConnectionDetailsView: View {
    let deviceInfo: DeviceInfo
    let dataTransfer: DataTransferInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Connection")
            VStack(alignment: .leading, spacing: 0) {
                InfoRow("MTU", deviceInfo.mtuBytes.map { "\($0) bytes" } ?? "—")
                InfoRow("Write Mode", deviceInfo.writeWithoutResponse ? "Without Response" : "With Response")
                InfoRow("Total Sent", "\(dataTransfer.totalSentBytes) bytes")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
        .padding(.horizontal)
    }
}

struct DataStreamView: View {
    let dataTransfer: DataTransferInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Data Stream")
            VStack(alignment: .leading, spacing: 8) {
                if dataTransfer.lastSentBytes > 0 {
                    Text("Sent \(dataTransfer.lastSentBytes) bytes")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                DataPreviewBox(title: "Last Sent", content: dataTransfer.lastSent)
                DataPreviewBox(title: "Location Preview", content: dataTransfer.locationText)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
        .padding(.horizontal)
    }
}

struct DataPreviewBox: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(content)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.05))
                .cornerRadius(4)
        }
    }
}

struct ErrorView: View {
    let error: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Error")
            Text(error)
                .font(.system(size: 12))
                .foregroundColor(.red)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
        }
        .padding(.horizontal)
    }
}

struct ControlsView: View {
    @ObservedObject var viewModel: BluetoothViewModel
    @FocusState.Binding var isTextFieldFocused: Bool
    let isConnected: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Controls")
            
            HStack {
                TextField("Enter text to send", text: $viewModel.textToSend)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 14))
                    .focused($isTextFieldFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        viewModel.sendText()
                    }
                
                Button("Send") {
                    viewModel.sendText()
                }
                .font(.system(size: 14))
                .disabled(!isConnected)
            }
            
            Button(action: { viewModel.sendLocation() }) {
                Text("Send GPS Coordinates")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .disabled(!isConnected)
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
}

struct ConnectButton: View {
    @ObservedObject var viewModel: BluetoothViewModel
    
    var body: some View {
        Button(action: {
            switch viewModel.connectionState {
            case .connected:
                viewModel.disconnect()
            case .scanning:
                break // Do nothing while scanning
            default:
                viewModel.scanForDevices()
            }
        }) {
            Text(buttonText)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.connectionState == .scanning)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
    }
    
    private var buttonText: String {
        switch viewModel.connectionState {
        case .connected:
            return "Disconnect"
        case .scanning:
            return "Scanning..."
        case .connecting:
            return "Connecting..."
        case .disconnected:
            return "Connect"
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    let isMonospace: Bool
    
    init(_ label: String, _ value: String, monospace: Bool = false) {
        self.label = label
        self.value = value
        self.isMonospace = monospace
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(isMonospace ? .system(size: 13, design: .monospaced) : .system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(2)
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }
}
