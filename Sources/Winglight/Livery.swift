import Foundation
import SwiftUI
import WinglightCore

struct Livery: Codable, Identifiable, Hashable {
    let id: String
    let code: String
    let title: String
    let english: String
    let region: String
    let aircraft: String
    let texture: String
    let engineTexture: String?
    var model: String? = nil
    var textures: [String]? = nil
    var special: Bool? = nil
    var textureSize: [Int]? = nil
    var resolutionLabel: String { textureSize.map { "\($0[0]) × \($0[1])" } ?? "\(resolution) × \(resolution)" }
    let resolution: Int
    let note: String
    func asset(for aircraft: Aircraft) -> String { model ?? aircraft.defaultAsset }
    var atlasURLs: [URL]? {
        guard let textures else { return nil }
        let urls=textures.compactMap { WinglightResources.bundle.url(forResource:$0,withExtension:nil,subdirectory:"Liveries") }
        return urls.count == textures.count ? urls : nil
    }
    var rawValue: String { id }
    var isNeutral: Bool { id == "neutral" }
    var textureURL: URL? { WinglightResources.bundle.url(forResource:texture,withExtension:nil,subdirectory:"Liveries") }
    var engineURL: URL? {
        if let engineTexture { return WinglightResources.bundle.url(forResource:engineTexture,withExtension:nil,subdirectory:"Liveries") }
        return WinglightResources.bundle.url(forResource:"engine-CFM56",withExtension:"png",subdirectory:"Textures")
    }
    static let neutral = Livery(id:"neutral",code:"",title:"素色",english:"Unpainted",region:"",aircraft:"",texture:"",engineTexture:nil,resolution:0,note:"")
    static let catalog: [Livery] = {
        guard let url=WinglightResources.bundle.url(forResource:"catalog",withExtension:"json",subdirectory:"Liveries"),let data=try? Data(contentsOf:url),let result=try? JSONDecoder().decode([Livery].self,from:data) else { return [] }
        return result
    }()
    static func available(for aircraft: Aircraft) -> [Livery] { catalog.filter { $0.aircraft == aircraft.rawValue } }
    static func defaultLivery(for aircraft: Aircraft) -> Livery { available(for:aircraft).first { $0.code == "CCA" } ?? available(for:aircraft).first ?? .neutral }
    static var airChina: Livery { defaultLivery(for:.airbus) }
    static func matching(_ query: String,aircraft: Aircraft) -> Livery? {
        if query == "neutral" { return .neutral }
        return available(for:aircraft).first { $0.id == query || $0.code.caseInsensitiveCompare(query) == .orderedSame }
    }
    func matches(_ query: String) -> Bool {
        let q=query.trimmingCharacters(in:.whitespacesAndNewlines)
        let aliases: [String:String] = ["CCA":"国航 中国国际航空","CSN":"南航 中国南方航空","CXA":"厦航 厦门航空","CES":"东航","CHH":"海航","CAL":"华航","DAL":"达美","DLH":"汉莎","QFA":"澳航 澳洲航空","BAW":"英航","AFR":"法航","ACA":"加航","UAL":"美联航 美国联合航空","JAL":"日航","ANA":"全日空","KAL":"大韩","KLM":"荷航","SWR":"瑞航"]
        return q.isEmpty || [title,english,code,aliases[code] ?? ""].contains { $0.localizedStandardContains(q) }
    }
}

struct LiveryPicker: View {
    @ObservedObject var state: AppState
    @State private var search = ""
    @State private var region = "全部"
    @State private var favoritesOnly = false
    @State private var specialsOnly = false
    @FocusState private var searchFocused: Bool
    private var available: [Livery] { Livery.available(for:state.settings.aircraft) }
    private var filtered: [Livery] {
        available.filter { $0.matches(search) && (region == "全部" || $0.region == region) && (!favoritesOnly || state.favoriteLiveries.contains($0.id)) && (!specialsOnly || $0.special == true || $0.code.hasPrefix("CCA-")) }
    }
    private var regionPicker: some View {
        Picker("地区",selection:$region) {
            ForEach(["全部","中国","亚洲与中东","欧洲","美洲","大洋洲","非洲"],id:\.self) { Text($0).tag($0) }
        }.frame(maxWidth:190)
    }
    private var filterButtons: some View {
        HStack {
            Toggle(isOn:$favoritesOnly) { Label("收藏",systemImage:"star") }.toggleStyle(.button)
            Toggle("彩绘",isOn:$specialsOnly).toggleStyle(.button)
            Button("素色") { state.chooseLivery(.neutral) }
        }.controlSize(.small).fixedSize()
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                VStack(alignment:.leading,spacing:5) {
                    Text("涂装库").font(.system(size:23,weight:.semibold,design:.rounded))
                    Text("\(state.settings.aircraft.title) · \(available.count) 款内置涂装").font(.system(size:12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { state.showLiveries=false } label: { Image(systemName:"xmark").font(.system(size:12,weight:.semibold)).frame(width:28,height:28).background(.primary.opacity(0.07),in:Circle()) }
                    .buttonStyle(.plain).accessibilityLabel("关闭涂装库")
            }
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索航空公司或代码",text:$search).textFieldStyle(.plain).focused($searchFocused).submitLabel(.search).onSubmit { searchFocused=false }
                if !search.isEmpty { Button { search="" } label: { Image(systemName:"xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
            }.padding(11).background(.primary.opacity(0.05),in:RoundedRectangle(cornerRadius:11))
            ViewThatFits(in:.horizontal) {
                HStack { regionPicker;filterButtons }
                VStack(alignment:.leading,spacing:12) { regionPicker;filterButtons }
            }
            ScrollView {
                LazyVStack(spacing:6) {
                    ForEach(filtered) { livery in
                        HStack(spacing:10) {
                            Button { state.chooseLivery(livery) } label: {
                                HStack(spacing:13) {
                                    Text(livery.code.prefix(3)).font(.system(size:11,weight:.semibold,design:.monospaced))
                                        .frame(width:42,height:42).background(.tint.opacity(0.10),in:RoundedRectangle(cornerRadius:10))
                                    VStack(alignment:.leading,spacing:4) {
                                        Text(livery.title).font(.system(size:13,weight:.medium))
                                        Text((livery.special == true ? "彩绘 · " : "") + livery.english).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    VStack(alignment:.trailing,spacing:4) {
                                        Text(livery.resolutionLabel).font(.system(size:10,weight:.medium,design:.monospaced)).foregroundStyle(.secondary)
                                        if state.livery.id == livery.id { Image(systemName:"checkmark.circle.fill").foregroundStyle(.tint) }
                                    }.frame(width:100,alignment:.trailing).lineLimit(1)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Button { state.toggleFavorite(livery) } label: {
                                Image(systemName:state.favoriteLiveries.contains(livery.id) ? "star.fill" : "star").foregroundStyle(state.favoriteLiveries.contains(livery.id) ? Color.orange : Color.secondary).frame(width:44,height:44)
                            }.buttonStyle(.plain).help("收藏 \(livery.title)")
                        }.padding(10).background(state.livery.id == livery.id ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:12))
                    }
                    if filtered.isEmpty { ContentUnavailableView("没有匹配的涂装",systemImage:"magnifyingglass",description:Text("试试航空公司中文名、英文名或三字代码。")) }
                }
            }.scrollDismissesKeyboard(.interactively).panelViewport(height:340)
            HStack(alignment:.top,spacing:10) {
                if state.liveryLoading { ProgressView().controlSize(.small) }
                VStack(alignment:.leading,spacing:4) {
                    Text(state.liveryLoading ? "正在载入 \(state.livery.title)…" : state.livery.title).font(.system(size:12,weight:.medium))
                    Text(state.liveryError ?? state.livery.note).font(.system(size:10)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }
                Spacer()
                Button("完成") { state.showLiveries=false }.buttonStyle(.borderedProminent)
            }.frame(minHeight:36)
        }.padding(24).desktopPanel(width:550).onAppear {
            #if os(macOS)
            searchFocused=true
            #endif
        }
    }
}
