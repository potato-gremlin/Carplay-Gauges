import SwiftUI

/// Pages horizontally through the user's configured gauge pages, like Dr. Prius's swipeable screens.
struct GaugesScreen: View {
    let layoutStore: GaugeLayoutStore
    let store: VehicleDataStore
    @State private var selectedPageID: GaugePageConfig.ID?

    var body: some View {
        TabView(selection: $selectedPageID) {
            ForEach(layoutStore.layout.pages) { page in
                GaugePageView(page: page, store: store, unitSystem: layoutStore.layout.unitSystem)
                    .tag(Optional(page.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            if selectedPageID == nil { selectedPageID = layoutStore.layout.pages.first?.id }
        }
    }
}
