import SwiftUI
import WinglightCore

struct AircraftPicker: View {
    @ObservedObject var state: AppState
    @State private var search=""
    private var aircraft: [Aircraft] { Aircraft.allCases.filter { search.isEmpty || ($0.title+" "+$0.shortName).localizedStandardContains(search) } }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                VStack(alignment:.leading,spacing:5) {
                    Text("机型库").font(.system(size:23,weight:.semibold,design:.rounded))
                    Text("\(Aircraft.allCases.count) 种机型 · \(Livery.catalog.count) 款涂装").font(.system(size:12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { state.showAircraft=false } label: { Image(systemName:"xmark").frame(width:28,height:28).background(.primary.opacity(0.07),in:Circle()) }.buttonStyle(.plain).accessibilityLabel("关闭机型库")
            }
            HStack { Image(systemName:"magnifyingglass");TextField("搜索机型，例如 77W、787、A350",text:$search).textFieldStyle(.plain) }.padding(12).background(.primary.opacity(0.05),in:RoundedRectangle(cornerRadius:11))
            ScrollView {
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                    ForEach(aircraft) { model in
                        Button {
                            state.select(model);state.showAircraft=false
                        } label: {
                            VStack(alignment:.leading,spacing:10) {
                                HStack { Text(model.maker).font(.system(size:9,weight:.semibold)).tracking(1.2);Spacer();if state.settings.aircraft==model { Image(systemName:"checkmark.circle.fill").foregroundStyle(.tint) } }.foregroundStyle(.secondary)
                                Text(model.modelName).font(.system(size:21,weight:.semibold,design:.rounded))
                                Text(String(format:"机长 %.2f m · 翼展 %.2f m",model.length,model.span)).font(.system(size:10)).foregroundStyle(.secondary)
                                Text("\(Livery.available(for:model).count) 款涂装").font(.system(size:11,weight:.medium)).foregroundStyle(.tint)
                            }.frame(maxWidth:.infinity,alignment:.leading).padding(15).background(state.settings.aircraft==model ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:14))
                        }.buttonStyle(.plain).accessibilityLabel(model.title)
                    }
                }
            }.frame(height:416)
        }.padding(24).frame(width:570)
    }
}
