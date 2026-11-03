//
//  AppView.swift
//  NSG
//
//  Created by forLG on 2026/11/3.
//

import SwiftUI

struct AppView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var isLaunched: Bool = false
    
    var body: some View {
        NavigationStack {
            // TODO: Defalut is a emtpy view, after the toggle on the .topbarTrailing is open, push the setting view
        }
        .animation(reduceMotion ? nil: .smooth(duration: 0.3), value: isLaunched)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar{
            ToolbarItem(placement: .topBarLeading) {
                Text("Nikon Smart GPS")
                    .font(.title2)
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                // TODO: toggle to start the bluetooth
                // set isLaunched -> true
            }
            
            ToolbarItem(placement: .bottomBar) {
                // TODO: setting menu
            }
        }
    }
}

#if DEBUG
#Preview {
    AppView()
}
#endif
