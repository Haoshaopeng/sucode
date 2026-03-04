import SwiftUI

struct AddDeviceView: View {
    @ObservedObject var deviceManager: DeviceManager
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Device Info")) {
                    TextField("Name", text: $name)
                    TextField("Host", text: $host)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                }

                Section(header: Text("Authentication")) {
                    TextField("Username", text: $username)
                        .autocapitalization(.none)
                    SecureField("Password", text: $password)
                }
            }
            .navigationTitle("Add Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveDevice()
                    }
                    .disabled(name.isEmpty || host.isEmpty || username.isEmpty)
                }
            }
        }
    }

    func saveDevice() {
        let device = Device(
            name: name,
            host: host,
            port: Int(port) ?? 22,
            username: username,
            password: password
        )
        deviceManager.addDevice(device)
        dismiss()
    }
}
