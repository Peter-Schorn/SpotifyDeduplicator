//
//  DeDuplicateView.swift
//  SpotifyDeduplicator
//
//  Created by Peter Schorn on 9/7/20.
//  Copyright © 2020 Peter Schorn. All rights reserved.
//

import SwiftUI

struct DeDuplicateView: View {
    
    @EnvironmentObject var spotify: Spotify
    
    var body: some View {
        
        Button(action: deDuplicate) {
            Text("De-Depulicate")
                .font(.title)
                .fontWeight(.light)
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .background(Color.green)
                .clipShape(Capsule())
                .shadow(radius: 10)
                .onTapGesture(perform: deDuplicate)
        }
        .buttonStyle(PlainButtonStyle())
        
    }
    
    func deDuplicate() {
        print("de-duplicating")
    }
    
}

struct DeDuplicateView_Previews: PreviewProvider {
    static var previews: some View {
        DeDuplicateView()
    }
}
