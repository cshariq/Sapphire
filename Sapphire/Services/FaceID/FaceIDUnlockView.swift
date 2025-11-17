//
//  FaceIDUnlockView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-16.
//

import SwiftUI

struct FaceIDUnlockView: View {
    @State private var isUnlocked = false
    @State private var animateRing = false

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)

            VStack {
                ZStack {
                    Circle()
                        .stroke(lineWidth: 4)
                        .foregroundColor(.green)
                        .scaleEffect(animateRing ? 1.2 : 1)
                        .opacity(animateRing ? 0 : 1)
                        .animation(Animation.easeOut(duration: 1).repeatForever(autoreverses: false), value: animateRing)

                    Image(systemName: "faceid")
                        .font(.system(size: 80))
                        .foregroundColor(.green)
                        .scaleEffect(isUnlocked ? 1.2 : 1)
                        .rotationEffect(.degrees(isUnlocked ? 360 : 0))
                        .animation(.spring(response: 0.5, dampingFraction: 0.6, blendDuration: 0), value: isUnlocked)
                }
                .onAppear {
                    animateRing = true
                }

                if isUnlocked {
                    Text("Unlocked")
                        .font(.title)
                        .foregroundColor(.green)
                        .transition(.opacity)
                        .animation(.easeIn(duration: 0.5), value: isUnlocked)
                }
            }
        }
        .onTapGesture {
            withAnimation {
                isUnlocked.toggle()
            }
        }
    }
}

struct FaceIDUnlockView_Previews: PreviewProvider {
    static var previews: some View {
        FaceIDUnlockView()
    }
}