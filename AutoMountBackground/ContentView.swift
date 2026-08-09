//
//  ContentView.swift
//  AutoMountBackground
//
//  Created by Mark Tassinari on 12/27/25.
//

import SwiftUI
import libMounter


struct ContentView: View {
    /// Height of a single share row: the label plus its 6pt vertical padding.
    private static let rowHeight: CGFloat = 30
    /// Roughly eight rows, after which the list scrolls.
    private static let maxListHeight: CGFloat = 240

    let model : ShareDataModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("common.app_name")
                    .font(.body)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    model.openApp()
                } label: {
                    Text("background.button.settings")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding([.top], 12)
            .padding([.leading, .trailing], 20)
           
            Divider()
                .padding([.leading, .trailing], 20)
                .padding([.top], 12)
            List() {
                if !model.shares.isEmpty {
                    ForEach(model.shares, id:\.self) { share in
                        ContentCellView(share: share) { passedShare, type in
                            switch type{
                                
                            case .open:
                                // Only a mounted share has somewhere to reveal; opening an
                                // unmounted one would just bounce Finder off a dead path.
                                if passedShare.connected == .mounted {
                                    passedShare.open()
                                }
                            case .mount:
                                Task{
                                    do{
                                        switch passedShare.connected{
                                            
                                        case .mounted:
                                            _ = try await  model.unmount(passedShare)
                                        case .unmounted:
                                            _ = try await  model.mount(passedShare)
                                        default:
                                            break
                                        }
                                       
                                    }catch{
                                        AutoMountBackground.error("mount/unmout error \(String(describing: error))")
                                    }
                                }
                               
                            }
                        }
                    }

                }else{
                    Text("background.empty_state")
                }
            }
            .listStyle(.plain)
            // The popup sizes itself to its content, and a List has no
            // intrinsic height, so it needs an explicit one. Sized to the rows
            // present but capped, so a long share list scrolls instead of
            // growing a menu taller than the screen.
            .frame(height: min(CGFloat(max(model.shares.count, 1)) * Self.rowHeight,
                               Self.maxListHeight))
            .padding([.top, .bottom], 12)

        }
        .frame(width: 280)
        
        
    }
}
enum ButtonActionType{
    case open, mount
}

extension Share{
    var textColor : Color{
        connected == .mounted || connected == .unmounting  ? .primary : .secondary
    }
    var buttonDisabled : Bool{
        connected == .mounting || connected == .unmounting
    }
}


struct ContentCellView: View {
    @State private var hovering = false
    var share: Share
    let actionHandler : (Share, ButtonActionType) -> Void
    
    var body: some View {
        // The row and the mount button are siblings, not nested. Nesting the mount button
        // inside the row button's label made a single click on eject fire *both* actions —
        // so ejecting also asked Finder to reveal the volume being unmounted.
        HStack(spacing: 0){
            Button {
                actionHandler(share, .open)
            } label: {
                Text(share.name ?? "--")
                    .foregroundStyle(share.textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())  //allows taps on empty space in cell
            }
            .buttonStyle(.plain)

            Button {
                actionHandler(share, .mount)
            } label: {
                switch share.connected {
                case .mounted:
                    Image(systemName: "eject")
                case .unmounted:
                    Image(systemName: "arrow.up.circle")
                case .mounting, .unmounting:
                    ProgressView()
                        .controlSize(.mini)
                            .frame(width: 16, height: 16)
                }

            }
            .buttonStyle(.borderless)
            .disabled(share.buttonDisabled)
        }
        .padding([.leading, .trailing],12)
        .padding([.top, .bottom],6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                               .fill(hovering ? Color.gray.opacity(0.15) : .clear)
        )
        .onHover(perform: {
            if share.connected == .mounted{
                self.hovering = $0
            }
            else {self.hovering = false}
        })
        
    }
}


#Preview {
    ContentView(model: MockStore.store)
}
