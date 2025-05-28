# Crackle 

## Features

- Real-time audio analysis
- Bluetooth device support
- Speaker output capability
- Distortion detection algorithms
- Signal alignment and comparison
- Clipping detection
- (Planned) Crackling detection
- (Planned) Spectral comparison

## Technical Details

The app uses:
- SwiftUI for the user interface
- AVFoundation for audio processing
- Accelerate framework for high-performance signal processing
- Cross-correlation for signal alignment
- Buffer-based audio processing

## Requirements

- iOS 15.0+ / macOS 12.0+
- Xcode 13.0+
- Swift 5.5+

## Installation

1. Clone the repository
2. Open `Crackle - Stop Bluetooth speaker crackling.xcodeproj` in Xcode
3. Build and run the project

## Usage

1. Launch the app
2. Connect your Bluetooth speaker
3. Press "Start Analysis" to begin the audio quality test
4. The app will play a reference signal and analyze the output
5. Results will be displayed on screen
6. Press "Stop Analysis" to end the test

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. 
