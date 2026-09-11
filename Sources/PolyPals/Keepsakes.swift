import Foundation

enum InventoryOrigin: String, Codable, Sendable {
    case legacy
    case userGift
    case petFound
}

struct GiftOption: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let symbol: String

    static let all: [GiftOption] = [
        .init(id: "cookie", title: "一块小饼干", symbol: "birthday.cake"),
        .init(id: "flower", title: "一朵小花", symbol: "camera.macro"),
        .init(id: "note", title: "一张小便签", symbol: "note.text"),
        .init(id: "badge", title: "一枚小徽章", symbol: "seal")
    ]
}

struct PetFoundKeepsake: Sendable, Equatable {
    let key: String
    let title: String
    let detail: String
    let symbol: String
}

enum PetKeepsakeCatalog {
    static func items(for petID: PetID) -> [PetFoundKeepsake] {
        switch petID {
        case .sol:
            return [
                .init(key: "sol-ticket", title: "一张皱掉的车票", detail: "Sol：“我不知道它通向哪里，所以当然要带回来。”\n¿Hasta dónde llega? —— 它会到哪里？", symbol: "ticket"),
                .init(key: "sol-postcard", title: "没有地址的明信片", detail: "Sol：“可能是写给还没认识的人。”\nSaludos desde aquí. —— 从这里向你问好。", symbol: "rectangle.portrait.on.rectangle.portrait"),
                .init(key: "sol-button", title: "一颗红色纽扣", detail: "Sol：“它看起来像某个故事的句号。”\nFalta algo. —— 好像少了什么。", symbol: "circle.circle"),
                .init(key: "sol-map", title: "一角手绘地图", detail: "Sol：“好消息：有路。坏消息：没画完。”\nPor aquí. —— 从这边走。", symbol: "map"),
                .init(key: "sol-ribbon", title: "一小段黄丝带", detail: "Sol：“风把它系在了我的尾巴上。”\nQué casualidad. —— 真巧。", symbol: "wind"),
                .init(key: "sol-coin", title: "一枚旧游戏币", detail: "Sol：“它还欠我一局游戏。”\nOtra vez. —— 再来一次。", symbol: "circle.hexagongrid"),
                .init(key: "sol-label", title: "写着好运的标签", detail: "Sol：“我们先收下，以后再验证。”\nBuena suerte. —— 祝你好运。", symbol: "tag"),
                .init(key: "sol-stone", title: "一颗像太阳的小石头", detail: "Sol：“这颗明显跟我一伙。”\nBrilla un poco. —— 它有一点闪。", symbol: "sun.max")
            ]
        case .mousse:
            return [
                .init(key: "mousse-sugar", title: "一包折得很整齐的糖", detail: "Mousse：“并不是所有秩序都需要解释。”\nUn peu de sucre. —— 一点糖。", symbol: "cube"),
                .init(key: "mousse-menu", title: "一张迷你菜单", detail: "Mousse：“字很少，选择仍需要品位。”\nJe choisis ceci. —— 我选这个。", symbol: "menucard"),
                .init(key: "mousse-label", title: "一枚金色小标签", detail: "Mousse：“包装得体，值得保留。”\nC'est joli. —— 它很漂亮。", symbol: "tag.fill"),
                .init(key: "mousse-napkin", title: "一张有花边的餐巾", detail: "Mousse：“它差一点就被不讲究地丢掉了。”\nAvec soin. —— 要用心。", symbol: "square.text.square"),
                .init(key: "mousse-stamp", title: "一枚蓝色邮票", detail: "Mousse：“它的旅程比边缘的锯齿更有趣。”\nBon voyage. —— 一路顺风。", symbol: "envelope"),
                .init(key: "mousse-key", title: "一把很小的钥匙", detail: "Mousse：“暂时没有锁配得上它。”\nOn verra. —— 以后再看。", symbol: "key"),
                .init(key: "mousse-receipt", title: "一张干净的小票", detail: "Mousse：“细节才会记得我们来过。”\nC'est noté. —— 记下了。", symbol: "receipt"),
                .init(key: "mousse-leaf", title: "一片对称的叶子", detail: "Mousse：“自然偶尔也懂排版。”\nParfait. —— 完美。", symbol: "leaf")
            ]
        case .ash:
            return [
                .init(key: "ash-bookmark", title: "一枚忘了页码的书签", detail: "Ash: “A bookmark without a book. Admirably independent.”\nLost the page, kept the place.", symbol: "bookmark"),
                .init(key: "ash-note", title: "一张写着 perhaps 的纸片", detail: "Ash: “A complete argument, by some standards.”\nPerhaps. —— 也许。", symbol: "note.text"),
                .init(key: "ash-feather", title: "一根不属于 Ash 的羽毛", detail: "Ash: “Before you ask: no, it isn't mine.”\nA reasonable question.", symbol: "wind"),
                .init(key: "ash-clipping", title: "一角旧剪报", detail: "Ash: “The headline survived. The context did not.”\nContext matters. —— 语境很重要。", symbol: "newspaper"),
                .init(key: "ash-pencil", title: "一截很短的铅笔", detail: "Ash: “Still capable of one excellent sentence.”\nMake it count.", symbol: "pencil"),
                .init(key: "ash-card", title: "一张空白索引卡", detail: "Ash: “It contains every answer we haven't written yet.”\nBlank, not empty.", symbol: "rectangle.on.rectangle"),
                .init(key: "ash-pin", title: "一枚星形图钉", detail: "Ash: “For pinning down unusually mobile ideas.”\nHold that thought.", symbol: "pin"),
                .init(key: "ash-thread", title: "一段深蓝色线头", detail: "Ash: “A loose thread. Naturally, I investigated.”\nFollow the thread.", symbol: "scribble")
            ]
        }
    }
}

enum PetFoundItemPolicy {
    static let minimumInterval: TimeInterval = 6 * 60 * 60
    static let maximumUnread = 3

    static func shouldCreate(
        petID: PetID,
        now: Date,
        lastFoundAt: Date?,
        hasInteracted: Bool,
        unreadCount: Int,
        calendar: Calendar = .current
    ) -> Bool {
        guard hasInteracted, unreadCount < maximumUnread else { return false }
        if let lastFoundAt {
            if calendar.isDate(lastFoundAt, inSameDayAs: now) { return false }
            if now.timeIntervalSince(lastFoundAt) < minimumInterval { return false }
        }
        let day = calendar.ordinality(of: .day, in: .year, for: now) ?? 0
        let offset = PetID.allCases.firstIndex(of: petID) ?? 0
        return (day + offset * 2) % 3 != 0
    }
}
