//
//  ContentView.swift
//  Crackle -  Stop Bluetooth speaker crackling
//
//  Created by Arjun Singh on 5/21/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var audioProcessor = AudioProcessor()

    var body: some View {
        VStack {
            Image(systemName: "speaker.wave.2.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Distortion Detector")

            Spacer()

            Button("Start Analysis") {
                audioProcessor.startProcessing()
            }
            .padding()

            Button("Stop Analysis") {
                audioProcessor.stopProcessing()
            }
            .padding()

            Spacer()

            // Display analysis results here
            Text(audioProcessor.analysisResult)
                .padding()

        }
        .padding()
    }
}

#Preview {
    ContentView()
}
