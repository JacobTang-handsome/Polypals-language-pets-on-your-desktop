import Foundation

enum SeedContent {
    static func cards(for petID: PetID) -> [GeneratedCard] {
        let original = switch petID {
        case .sol: sol
        case .mousse: mousse
        case .ash: ash
        }
        return original + ExpandedSeedContent.cards(for: petID)
    }

    static func package(for petID: PetID, energy: EnergyState, count: Int) -> [GeneratedCard] {
        let boundedCount = min(3, max(1, count))
        let preferredTypes: [CardType]
        switch energy {
        case .focused: preferredTypes = [.expression, .listening, .dialogue]
        case .tired: preferredTypes = [.listening, .picturePrompt, .expression]
        case .bored: preferredTypes = [.scenario, .dialogue, .picturePrompt]
        case .curious: preferredTypes = [.culture, .confusingWords, .expression]
        }
        let all = cards(for: petID)
        let ordered = preferredTypes.compactMap { type in all.first(where: { $0.type == type }) }
            + all.filter { !preferredTypes.contains($0.type) }
        return Array(ordered.prefix(boundedCount))
    }

    static func card(
        _ pet: PetID,
        _ type: CardType,
        _ language: String,
        _ level: String,
        _ seconds: Int,
        _ hook: String,
        _ target: String,
        _ prompt: String,
        _ choices: [String],
        _ answer: String,
        _ help: String,
        sourceTitle: String? = nil,
        sourceURL: String? = nil,
        key: String
    ) -> GeneratedCard {
        GeneratedCard(
            petID: pet,
            type: type,
            language: language,
            level: level,
            estimatedSeconds: seconds,
            hook: hook,
            targetText: target,
            prompt: prompt,
            choices: choices,
            answer: answer,
            chineseHelp: help,
            sourceTitle: sourceTitle,
            sourceURL: sourceURL,
            memoryKey: key
        )
    }

    static let sol: [GeneratedCard] = [
        card(.sol, .expression, "es", "B1", 45, "Sol 说它耳朵后面有只苍蝇。", "tener la mosca detrás de la oreja", "你觉得这表示什么？", ["很高兴", "开始怀疑", "非常疲惫"], "开始怀疑", "形容察觉到事情可能不对。", key: "es:tener-la-mosca"),
        card(.sol, .dialogue, "es", "B1", 60, "一段原创的雨天对白。", "—¿Trajiste el paraguas?\n—Claro. Lo dejé en casa para que no se mojara.", "第二个人的语气更接近哪一种？", ["认真", "无奈的幽默", "生气"], "无奈的幽默", "字面上说‘我把伞留在家里，免得它淋湿’。", key: "es:paraguas-dialogue"),
        card(.sol, .culture, "es", "B1", 75, "吃完饭不一定马上离桌。", "la sobremesa", "它通常发生在什么时候？", ["饭后聊天时", "早餐前", "赶火车时"], "饭后聊天时", "RAE 将其解释为吃完后仍留在桌边的时间。", sourceTitle: "Diccionario de la lengua española — sobremesa", sourceURL: "https://dle.rae.es/sobremesa", key: "es:culture-sobremesa"),
        card(.sol, .listening, "es", "B1", 35, "听 Sol 说一句。", "Hoy necesito un descanso corto.", "这句话最接近哪个意思？", ["今天我需要短暂休息", "今天我需要长途旅行", "今天我不想工作"], "今天我需要短暂休息", "可以慢速重听，不需要拼写。", key: "es:listening-descanso"),
        card(.sol, .scenario, "es", "B1", 90, "朋友迟到了十分钟。", "Perdona, llegué tarde.", "选一句自然回应。", ["No pasa nada.", "La mesa es azul.", "Tengo dos ventanas."], "No pasa nada.", "表示‘没关系’。", key: "es:scenario-late"),
        card(.sol, .confusingWords, "es", "B1", 70, "两个‘知道’并不完全一样。", "saber / conocer", "哪一个更适合表示认识一个人？", ["saber", "conocer"], "conocer", "saber 常用于知道事实或会做某事；conocer 常用于认识人或熟悉地方。", key: "es:saber-conocer"),
        card(.sol, .picturePrompt, "es", "B1", 80, "一只橙红色小狐狸正望向旁边。", "El zorro mira algo a su izquierda.", "看图用西语说任何一句；也可以从“El zorro…”开始。", [], "开放回答", "先表达意思，纠错默认折叠。", key: "es:picture-fox")
    ]

    static let mousse: [GeneratedCard] = [
        card(.mousse, .expression, "fr", "A1", 40, "Mousse 很认真地指着点心。", "J’ai faim.", "这句话是什么意思？", ["我饿了", "我累了", "我迷路了"], "我饿了", "avoir faim 表示‘饿’，法语里字面是‘有饥饿感’。", key: "fr:avoir-faim"),
        card(.mousse, .dialogue, "fr", "A1", 55, "一段原创咖啡馆对白。", "—Un café, s’il vous plaît.\n—Avec du lait ?", "店员在问什么？", ["要牛奶吗", "要糖吗", "要带走吗"], "要牛奶吗", "avec 表示‘和、带有’。", key: "fr:cafe-dialogue"),
        card(.mousse, .culture, "fr", "A1", 80, "法国人的节庆餐桌不仅关乎菜品。", "le repas gastronomique", "UNESCO 更强调什么？", ["共同庆祝与餐桌仪式", "只吃昂贵食物", "快速吃完"], "共同庆祝与餐桌仪式", "该项目描述的是庆祝重要时刻的社会习俗，包括选菜、摆桌和品尝。", sourceTitle: "UNESCO — Le repas gastronomique des Français", sourceURL: "https://ich.unesco.org/fr/RL/le-repas-gastronomique-des-francais-00437", key: "fr:culture-meal"),
        card(.mousse, .listening, "fr", "A1", 35, "听一个很短的问题。", "C’est une pomme ?", "Mousse 在问什么？", ["这是苹果吗", "苹果在哪里", "我要苹果"], "这是苹果吗", "C’est…? 是非常常用的简单确认句。", key: "fr:listening-pomme"),
        card(.mousse, .scenario, "fr", "A1", 75, "Mousse 想吃水果。", "Je voudrais une orange.", "选一句可以递给它的话。", ["Voilà une orange.", "Je suis une gare.", "Il fait un livre."], "Voilà une orange.", "voilà 可以表示‘给你、这就是’。", key: "fr:scenario-orange"),
        card(.mousse, .confusingWords, "fr", "A1", 65, "两个冠词只差一个字母。", "un / une", "pomme 应该搭配哪一个？", ["un", "une"], "une", "pomme 是阴性名词：une pomme。", key: "fr:un-une"),
        card(.mousse, .picturePrompt, "fr", "A1", 70, "小猎豹安静地坐着。", "Le petit guépard est assis.", "看图说一句；可以从“Le guépard…”开始。", [], "开放回答", "只要表达清楚即可；一次最多提示一个结构。", key: "fr:picture-cheetah")
    ]

    static let ash: [GeneratedCard] = [
        card(.ash, .expression, "en", "C1", 45, "Ash 对一个意外成功的程序点了点头。", "That worked against all odds.", "这句话的语气是什么？", ["结果本来很稳", "成功得出乎意料", "结果仍未发生"], "成功得出乎意料", "against all odds 强调困难条件下仍然成功。", key: "en:against-all-odds"),
        card(.ash, .dialogue, "en", "C1", 55, "一段原创的代码对白。", "—It finally passed.\n—Excellent. We can now begin wondering why.", "第二句主要是什么语气？", ["干幽默", "愤怒", "正式祝贺"], "干幽默", "它先承认成功，再暗示成功原因仍不可靠。", key: "en:passed-dialogue"),
        card(.ash, .culture, "en", "C1", 80, "Afternoon tea 的流行历史比一个著名传说更复杂。", "afternoon tea", "可靠历史研究提醒我们什么？", ["饮茶和点心习惯早于单一发明故事", "英国直到二十世纪才喝茶", "它只属于王室"], "饮茶和点心习惯早于单一发明故事", "Historic England 指出，相关日记与讽刺作品显示，闲暇阶层更早已有配点心饮茶的习惯。", sourceTitle: "Historic England — Where Does the English Habit of Afternoon Tea Come From?", sourceURL: "https://historicengland.org.uk/listing/what-is-designation/heritage-highlights/where-does-the-english-habit-of-afternoon-tea-come-from/", key: "en:culture-afternoon-tea"),
        card(.ash, .listening, "en", "C1", 35, "听 Ash 的一句冷静判断。", "The result is promising, not conclusive.", "它在区分什么？", ["有希望与已有定论", "速度与价格", "过去与未来"], "有希望与已有定论", "promising 表示前景好；conclusive 表示足以得出最终结论。", key: "en:listening-conclusive"),
        card(.ash, .scenario, "en", "C1", 85, "你需要礼貌地打断一个过长的会议。", "Could we return to the main question?", "哪一句最自然且不显攻击性？", ["Could we return to the main question?", "Stop talking now.", "This meeting is objectively bad."], "Could we return to the main question?", "Could we…? 将建议表达得更柔和。", key: "en:scenario-meeting"),
        card(.ash, .confusingWords, "en", "C1", 65, "两个词都像‘暗示’，责任却不同。", "imply / infer", "说话者给出暗示时用哪个？", ["imply", "infer"], "imply", "说话者 imply；听者根据线索 infer。", key: "en:imply-infer"),
        card(.ash, .picturePrompt, "en", "C1", 75, "一只猫头鹰安静地看着你，似乎已经有了评价。", "The owl looks politely unconvinced.", "看图用英语配一句字幕。", [], "开放回答", "可以追求自然语气，不必写成学术句子。", key: "en:picture-owl")
    ]
}
