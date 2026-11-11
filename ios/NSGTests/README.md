# NSG tests

The tests use Swift Testing. Run the NSG scheme's test action on an iOS simulator.
Each test owns an isolated UserDefaults suite; camera transport, location input,
and camera deadlines are injected.

## File organization

| Directory | Responsibility |
| --- | --- |
| App | App service switches, startup policy, and settings persistence/application |
| Bluetooth | Bluetooth write queue behavior |
| Camera | Shared reconnection timing policy |
| Camera/Nikon | Camera matching and service flows for discovery, pairing, reconnection, and GPS transfer |
| Camera/Nikon/Protocol | Nikon wire formats, handshake state machine, and capability/scan policies |
| Camera/Nikon/Persistence | Nikon camera records, controller identities, reconnect preferences, and repository behavior |
| Location | Fix quality, coordinate conversion, and the location write lifecycle |
| Support | Fake transport, fake location source, manual scheduler, and shared camera setup |
