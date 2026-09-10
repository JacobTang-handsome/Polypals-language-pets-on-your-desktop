import Foundation

/// Reviewed, deterministic offline expansion: five additional cards per type
/// for every built-in pet (35 each). Together with SeedContent this is 42 per
/// pet and 126 total.
enum ExpandedSeedContent {
    static func cards(for pet: PetID) -> [GeneratedCard] {
        switch pet { case .sol: sol; case .mousse: mousse; case .ash: ash }
    }

    private static func c(
        _ pet: PetID, _ type: CardType, _ seconds: Int, _ target: String, _ prompt: String,
        _ choices: [String], _ answer: String, _ help: String, _ key: String,
        hook: String = "一段新的小发现。", source: (String, String)? = nil
    ) -> GeneratedCard {
        let definition = PetDefinition.definition(for: pet)
        let recurrence: (concept: String, origin: String?)? = switch key {
        case "es:listen-keys": ("es:concept-keys", nil)
        case "es:dialogue-keys", "es:picture-shoe": ("es:concept-keys", "es:listen-keys")
        case "fr:dialogue-cafe2", "fr:picture-coffee": ("fr:cafe-dialogue", "fr:cafe-dialogue")
        case "en:dialogue-fix", "en:picture-success": ("en:passed-dialogue", "en:passed-dialogue")
        default: nil
        }
        return GeneratedCard(
            petID: pet, type: type, language: pet == .sol ? "es" : pet == .mousse ? "fr" : "en",
            level: definition.level, estimatedSeconds: seconds, hook: hook, targetText: target,
            prompt: prompt, choices: choices, answer: answer, chineseHelp: help,
            sourceTitle: source?.0, sourceURL: source?.1, memoryKey: key,
            conceptKey: recurrence?.concept, originMemoryKey: recurrence?.origin
        )
    }

    static let sol: [GeneratedCard] = [
        c(.sol,.expression,45,"ponerse las pilas","更接近哪种意思？",["开始认真行动","去买电池","准备睡觉"],"开始认真行动","表示振作起来、加把劲。","es:ponerse-las-pilas",hook:"Sol 抱来一盒并不存在的电池。"),
        c(.sol,.expression,45,"estar hecho polvo","说话者大概感觉如何？",["筋疲力尽","特别幸运","非常整洁"],"筋疲力尽","口语中表示累坏了。","es:hecho-polvo",hook:"Sol 今天决定诚实描述自己的状态。"),
        c(.sol,.expression,50,"no tener pelos en la lengua","它形容怎样的人？",["说话直率","声音很小","总是忘词"],"说话直率","形容直言不讳。","es:pelos-lengua",hook:"这当然不是一堂生物课。"),
        c(.sol,.expression,45,"echar una mano","朋友在请求什么？",["帮个忙","挥挥手","离开这里"],"帮个忙","常用来表示帮助某人。","es:echar-mano",hook:"Sol 需要的手并不是字面意义上的。"),
        c(.sol,.expression,50,"quedarse de piedra","更接近哪种反应？",["震惊得愣住","安静地坐下","觉得很冷"],"震惊得愣住","表示因为惊讶而呆住。","es:de-piedra",hook:"一个意外结局让 Sol 停了两秒。"),
        c(.sol,.dialogue,60,"—¿Vienes mañana?\n—Si el despertador coopera.","第二句是什么语气？",["带幽默的保留","明确拒绝","正式承诺"],"带幽默的保留","如果闹钟配合的话，暗示不完全确定。","es:dialogue-alarm",hook:"一段原创的明日计划。"),
        c(.sol,.dialogue,60,"—¿Está listo?\n—Listo para fallar con elegancia.","回应者在做什么？",["开玩笑降低预期","宣布成功","责怪对方"],"开玩笑降低预期","字面是‘准备好优雅地失败’。","es:dialogue-elegance",hook:"Sol 对一个尚未运行的程序很有信心。"),
        c(.sol,.dialogue,55,"—Llegas tarde.\n—Traigo una excelente excusa.","第二个人想先做什么？",["解释迟到","结束谈话","点餐"],"解释迟到","traer una excusa 表示带着一个借口来。","es:dialogue-excuse",hook:"原创的迟到现场。"),
        c(.sol,.dialogue,65,"—¿Más café?\n—Mi código dice que sí.","回答把决定归给了什么？",["代码","医生","天气"],"代码","一种夸张的幽默回应。","es:dialogue-coffee",hook:"咖啡与代码展开了谈判。"),
        c(.sol,.dialogue,60,"—¿Perdimos las llaves?\n—Prefiero decir que están explorando.","第二句如何重述问题？",["把丢失说成探险","否认钥匙存在","责怪朋友"],"把丢失说成探险","用拟人化缓和小麻烦。","es:dialogue-keys",hook:"钥匙开始了未经批准的旅行。"),
        c(.sol,.culture,75,"la siesta","传统上它指什么？",["午后短暂休息","晚餐后的散步","周末早餐"],"午后短暂休息","RAE 将 siesta 解释为午餐后用于睡眠或休息的时间。","es:culture-siesta",hook:"一个被许多人认识、也常被简化的词。",source:("RAE — siesta","https://dle.rae.es/siesta")),
        c(.sol,.culture,80,"el Camino de Santiago","UNESCO 项目强调了什么？",["历史朝圣路线网络","单一城市公园","一种菜谱"],"历史朝圣路线网络","它由通往圣地亚哥的历史路线构成。","es:culture-camino",hook:"Sol 展开一张很长的地图。",source:("UNESCO — Routes of Santiago de Compostela","https://whc.unesco.org/en/list/669/")),
        c(.sol,.culture,75,"el flamenco","它在 UNESCO 名录中属于什么？",["非物质文化遗产","自然保护区","现代建筑"],"非物质文化遗产","UNESCO 将 flamenco 列入人类非物质文化遗产代表作名录。","es:culture-flamenco",hook:"今天的节奏来自一个有来源的小知识。",source:("UNESCO — Flamenco","https://ich.unesco.org/en/RL/flamenco-00363")),
        c(.sol,.culture,70,"la Ñ","它是什么？",["西班牙语字母表中的字母","只是一种重音符号","一个数字"],"西班牙语字母表中的字母","RAE 将 ñ 作为独立字母收录。","es:culture-enye",hook:"Sol 带来一个很有辨识度的字母。",source:("RAE — ñ","https://dle.rae.es/%C3%B1")),
        c(.sol,.culture,75,"el mate","这一传统与什么有关？",["共享饮用的草本饮品","一种舞步","一件乐器"],"共享饮用的草本饮品","相关传统涉及种植、制备和分享马黛茶。","es:culture-mate",hook:"同一种语言连接着很多地方。",source:("UNESCO — Yerba mate cultural landscape","https://www.unesco.org/en/articles/yerba-mate")),
        c(.sol,.listening,35,"¿Tienes un minuto?","对方在问什么？",["你有一分钟吗","现在几点","你有硬币吗"],"你有一分钟吗","常见的轻量开场。","es:listen-minute"),
        c(.sol,.listening,40,"No encuentro mis llaves.","发生了什么？",["找不到钥匙","忘记了名字","错过了火车"],"找不到钥匙","encontrar 表示找到。","es:listen-keys"),
        c(.sol,.listening,40,"Podemos intentarlo otra vez.","这是一种什么提议？",["再试一次","立刻放弃","换个房间"],"再试一次","otra vez 表示再次。","es:listen-again"),
        c(.sol,.listening,35,"Hoy hace mucho viento.","天气怎样？",["风很大","非常热","正在下雪"],"风很大","hacer viento 表示刮风。","es:listen-wind"),
        c(.sol,.listening,40,"Me alegra verte.","说话者表达什么？",["见到你很高兴","需要离开","有点担心"],"见到你很高兴","alegrarse 表示感到高兴。","es:listen-glad"),
        c(.sol,.scenario,80,"¿Me pones un café, por favor?","适合在哪个场景说？",["咖啡馆点单","车站问路","电话告别"],"咖啡馆点单","西班牙常见的自然点单方式。","es:scene-coffee"),
        c(.sol,.scenario,85,"¿Cómo llego a la estación?","用户需要什么？",["去车站的路线","一张菜单","酒店房间"],"去车站的路线","cómo llego a… 用来询问如何到达。","es:scene-station"),
        c(.sol,.scenario,75,"¿Puedes repetirlo más despacio?","什么时候最有用？",["没听清时","已经完全明白时","准备付款时"],"没听清时","请对方更慢地重复。","es:scene-repeat"),
        c(.sol,.scenario,80,"Busco una farmacia.","说话者在找什么？",["药店","书店","面包店"],"药店","buscar 表示寻找。","es:scene-pharmacy"),
        c(.sol,.scenario,85,"La cuenta, por favor.","这句话通常用来做什么？",["结账","预订座位","赞美食物"],"结账","在餐厅请求账单。","es:scene-bill"),
        c(.sol,.confusingWords,65,"ser / estar","哪一个常用于临时状态？",["ser","estar"],"estar","estar 常表达状态或位置。","es:conf-ser-estar"),
        c(.sol,.confusingWords,65,"por / para","表示目的时通常用哪个？",["por","para"],"para","para 常用于目的或目标。","es:conf-por-para"),
        c(.sol,.confusingWords,70,"pero / perro","哪个词表示‘但是’？",["pero","perro"],"pero","单个 r 的 pero 是‘但是’，双 r 的 perro 是‘狗’。","es:conf-pero-perro"),
        c(.sol,.confusingWords,65,"bien / bueno","修饰动作‘做得好’常用哪个？",["bien","bueno"],"bien","bien 常作副词，bueno 常作形容词。","es:conf-bien-bueno"),
        c(.sol,.confusingWords,70,"llevar / traer","朝说话者方向带来常用哪个？",["llevar","traer"],"traer","traer 常表示带来；llevar 常表示带走或携带去别处。","es:conf-llevar-traer"),
        c(.sol,.picturePrompt,70,"Un zorro lleva una taza demasiado grande.","用一句西语描述或续写。",[],"开放回答","可以从 El zorro lleva… 开始。","es:picture-cup",hook:"一只狐狸和一只过大的杯子。"),
        c(.sol,.picturePrompt,75,"Hay tres libros y una naranja sobre la mesa.","任选一个细节说一句。",[],"开放回答","可以使用 Hay… 表示‘有’。","es:picture-table",hook:"桌面上出现了奇怪的组合。"),
        c(.sol,.picturePrompt,75,"La ventana está abierta y llueve.","描述天气或房间。",[],"开放回答","可以从 Está lloviendo… 开始。","es:picture-rain",hook:"窗边的短场景。"),
        c(.sol,.picturePrompt,80,"Dos amigos esperan un tren que no llega.","为其中一人配一句话。",[],"开放回答","可以使用 ¿Cuándo llega…?","es:picture-train",hook:"列车暂时保持神秘。"),
        c(.sol,.picturePrompt,75,"Una llave duerme dentro de un zapato.","用西语解释它为什么在那里。",[],"开放回答","任何合理或荒诞的解释都可以。","es:picture-shoe",hook:"失踪的钥匙被发现了。")
    ]

    static let mousse: [GeneratedCard] = makeMousse()
    static let ash: [GeneratedCard] = makeAsh()

    private static func makeMousse() -> [GeneratedCard] {
        let expressions = [
            ("Ça va ?","这句话常用来做什么？",["询问近况","询问价格","表示再见"],"询问近况","最基础的问候之一。","fr:ca-va"),
            ("D’accord.","它表示什么？",["好的、同意","不知道","很饿"],"好的、同意","简短表示同意或理解。","fr:daccord"),
            ("À bientôt !","什么时候说？",["希望很快再见","第一次见面","请求帮助"],"希望很快再见","表示‘回头见’。","fr:a-bientot"),
            ("C’est délicieux.","Mousse 在评价什么？",["食物很好吃","天气很冷","房间很大"],"食物很好吃","délicieux 表示美味。","fr:delicieux"),
            ("Pas de problème.","更接近哪个意思？",["没问题","我不知道","不可能"],"没问题","常用于轻松回应。","fr:pas-probleme")
        ].map { c(.mousse,.expression,40,$0.0,$0.1,$0.2,$0.3,$0.4,$0.5,hook:"Mousse 带来一句可以立即使用的话。") }
        let dialogues = [
            ("—Bonjour !\n—Bonjour, un café ?","第二个人提供什么？",["咖啡","房间","地图"],"咖啡","原创的简单咖啡馆对白。","fr:dialogue-cafe2"),
            ("—Tu as faim ?\n—Un peu.","回答者有多饿？",["有一点","完全不饿","非常饿"],"有一点","un peu 表示一点。","fr:dialogue-hungry"),
            ("—Où est le chat ?\n—Sous la table.","猫在哪里？",["桌子下面","门后","窗边"],"桌子下面","sous 表示在……下面。","fr:dialogue-cat"),
            ("—Il pleut.\n—J’ai un parapluie.","第二个人有什么？",["雨伞","外套","车票"],"雨伞","原创雨天对白。","fr:dialogue-rain"),
            ("—Merci !\n—Avec plaisir.","第二句是什么作用？",["礼貌回应感谢","请求付款","表达生气"],"礼貌回应感谢","avec plaisir 可表示‘乐意之至’。","fr:dialogue-thanks")
        ].map { c(.mousse,.dialogue,55,$0.0,$0.1,$0.2,$0.3,$0.4,$0.5,hook:"一段只有两句的原创场景。") }
        let cultures = [
            c(.mousse,.culture,75,"la baguette","UNESCO 收录的是哪方面？",["手工技艺和文化","一种建筑","一首歌曲"],"手工技艺和文化","传统法棍面包的手工知识与文化被列入非遗名录。","fr:culture-baguette",source:("UNESCO — Artisanal know-how and culture of baguette bread","https://ich.unesco.org/en/RL/artisanal-know-how-and-culture-of-baguette-bread-01883")),
            c(.mousse,.culture,75,"le fest-noz","它与什么相关？",["布列塔尼的节庆舞会","一种甜点","巴黎地铁"],"布列塔尼的节庆舞会","UNESCO 描述其为以传统舞蹈为核心的节庆聚会。","fr:culture-fest-noz",source:("UNESCO — Fest-Noz","https://ich.unesco.org/en/RL/fest-noz-festive-gathering-based-on-the-collective-practice-of-traditional-dances-of-brittany-00707")),
            c(.mousse,.culture,70,"le repas","法语词典中它首先指什么？",["进食的时刻或食物","一段旅行","一种衣服"],"进食的时刻或食物","Académie française 的词条列出用餐及其食物等意义。","fr:culture-repas",source:("Académie française — repas","https://www.dictionnaire-academie.fr/article/A9R1648")),
            c(.mousse,.culture,75,"la tapisserie d’Aubusson","它是什么传统？",["织毯技艺","奶酪制作","航海比赛"],"织毯技艺","Aubusson 挂毯技艺被列入非遗名录。","fr:culture-aubusson",source:("UNESCO — Aubusson tapestry","https://ich.unesco.org/en/RL/aubusson-tapestry-00250")),
            c(.mousse,.culture,75,"les savoir-faire du parfum à Grasse","这一遗产与什么有关？",["香水相关技艺","造船","玻璃吹制"],"香水相关技艺","包括香料植物种植、原料处理和调香。","fr:culture-grasse",source:("UNESCO — Perfume in Pays de Grasse","https://ich.unesco.org/en/RL/the-skills-related-to-perfume-in-pays-de-grasse-01207"))
        ]
        let listening = [
            ("Je suis fatigué.","说话者怎样？",["累了","饿了","迷路了"],"累了","fatigué 表示疲惫。","fr:listen-tired"),("Où est la gare ?","在问什么？",["车站在哪里","几点了","多少钱"],"车站在哪里","où 表示哪里。","fr:listen-station"),("Il fait froid.","天气如何？",["冷","热","刮风"],"冷","faire froid 表示天气冷。","fr:listen-cold"),("J’aime ce livre.","喜欢什么？",["这本书","这杯咖啡","这座城市"],"这本书","ce livre 表示这本书。","fr:listen-book"),("À demain !","什么时候再见？",["明天","今晚","下周"],"明天","demain 表示明天。","fr:listen-tomorrow")
        ].map { c(.mousse,.listening,35,$0.0,$0.1,$0.2,$0.3,$0.4,$0.5) }
        let scenarios = [
            ("Je voudrais un thé.","用户想要什么？",["茶","咖啡","水"],"茶","voudrais 是礼貌表达需求。","fr:scene-tea"),("Un billet, s’il vous plaît.","适合在哪里说？",["车站","图书馆","公园"],"车站","请求购买一张票。","fr:scene-ticket"),("Excusez-moi, où sont les toilettes ?","用户在找什么？",["洗手间","出口","餐厅"],"洗手间","礼貌问路。","fr:scene-toilet"),("C’est combien ?","用户在问什么？",["价格","时间","名字"],"价格","简单询价。","fr:scene-price"),("Je ne comprends pas.","什么时候使用？",["没有听懂","完全同意","准备离开"],"没有听懂","A1 很实用的求助句。","fr:scene-understand")
        ].map { c(.mousse,.scenario,70,$0.0,$0.1,$0.2,$0.3,$0.4,$0.5) }
        let confusing = [
            ("bonjour / bonsoir","晚上问候用哪个？",["bonjour","bonsoir"],"bonsoir","bonsoir 用于晚上。","fr:conf-greeting"),("ce / cette","阴性单数名词前用哪个？",["ce","cette"],"cette","cette 用于阴性单数。","fr:conf-ce-cette"),("mon / ma","阴性名词 maison 前通常用哪个？",["mon","ma"],"ma","ma maison。元音开头有特殊情况，稍后再学。","fr:conf-mon-ma"),("très / trop","表示‘太、过度’用哪个？",["très","trop"],"trop","très 是很，trop 常是太、过度。","fr:conf-tres-trop"),("ici / là","表示‘这里’用哪个？",["ici","là"],"ici","ici 表示这里，là 常表示那里。","fr:conf-ici-la")
        ].map { c(.mousse,.confusingWords,60,$0.0,$0.1,$0.2,$0.3,$0.4,$0.5) }
        let pictures = [
            ("Le guépard tient une petite pomme.","用一句法语描述。","可以从 Le guépard… 开始。","fr:picture-apple"),("Il y a un café sur la table.","说出你看到的一件东西。","Il y a 表示‘有’。","fr:picture-coffee"),("La fenêtre est ouverte.","描述窗户。","只需要一个短句。","fr:picture-window"),("Deux oranges sont dans le sac.","水果在哪里？","dans 表示在……里面。","fr:picture-bag"),("Le chat dort sur un livre.","给画面配一句话。","dort 表示正在睡。","fr:picture-book")
        ].map { c(.mousse,.picturePrompt,65,$0.0,$0.1,[],"开放回答",$0.2,$0.3,hook:"Mousse 摆好了一幅简单画面。") }
        return expressions + dialogues + cultures + listening + scenarios + confusing + pictures
    }

    private static func makeAsh() -> [GeneratedCard] {
        let expressions = [
            ("call it a day","What does it suggest?",["Stop working for now","Name the date","Begin again"],"Stop working for now","A natural way to end the work period.","en:call-day"),("a long shot","How likely is it?",["Unlikely but possible","Certain","Already finished"],"Unlikely but possible","A plan with a small chance of success.","en:long-shot"),("read the room","What skill is involved?",["Notice the social mood","Read aloud","Measure a room"],"Notice the social mood","It means adapting to the people and atmosphere.","en:read-room"),("on the same page","What does it mean?",["Share an understanding","Read one book","Disagree politely"],"Share an understanding","Often used when people align on a plan.","en:same-page"),("not my cup of tea","What is being expressed?",["A personal dislike","A drink order","A factual error"],"A personal dislike","A mild, idiomatic way to say something is not for you.","en:cup-tea")
        ].map { c(.ash,.expression,45,$0.0,$0.1,$0.2,$0.3,$0.4,$0.5,hook:"Ash returns with a phrase of suspicious usefulness.") }
        let dialogues = [
            ("—Did the fix work?\n—It moved the problem somewhere more interesting.","What is the tone?",["Dry humor","Formal praise","Panic"],"Dry humor","The problem is reframed rather than solved.","en:dialogue-fix"),("—Are you free?\n—Define free.","What does the reply imply?",["Probably busy","Definitely available","Confused about price"],"Probably busy","An intentionally evasive, humorous answer.","en:dialogue-free"),("—We need a quick meeting.\n—Those are historically rare.","What is being questioned?",["Whether it will be quick","Whether meetings exist","Who should attend"],"Whether it will be quick","The reply doubts the adjective, not the meeting.","en:dialogue-meeting"),("—Any progress?\n—Several educational mistakes.","How is failure reframed?",["As learning","As victory","As someone else's fault"],"As learning","An original line using understatement.","en:dialogue-progress"),("—Should we deploy?\n—The button remains regrettably clickable.","Is this enthusiastic approval?",["No","Yes","Impossible to tell"],"No","The dry wording signals hesitation.","en:dialogue-deploy")
        ].map { c(.ash,.dialogue,60,$0.0,$0.1,$0.2,$0.3,$0.4,$0.5,hook:"An original two-line scene, delivered without ceremony.") }
        let cultures = [
            c(.ash,.culture,75,"the Oxford English Dictionary","What does it document?",["The history and usage of English words","Only spelling tests","One regional accent"],"The history and usage of English words","The OED describes itself as a historical dictionary tracing word meanings and use.","en:culture-oed",source:("Oxford English Dictionary — About","https://www.oed.com/information/about-the-oed")),
            c(.ash,.culture,75,"The Globe","What is it associated with?",["Shakespearean theatre","Space research","A railway map"],"Shakespearean theatre","Shakespeare’s Globe presents the history of the original Globe theatres.","en:culture-globe",source:("Shakespeare's Globe — Our history","https://www.shakespearesglobe.com/discover/about-us/our-history/")),
            c(.ash,.culture,80,"Irish harping","How is it recognized by UNESCO?",["Intangible cultural heritage","A modern sport","A geological site"],"Intangible cultural heritage","Irish harping was inscribed on UNESCO's Representative List.","en:culture-harp",source:("UNESCO — Irish harping","https://ich.unesco.org/en/RL/irish-harping-01454")),
            c(.ash,.culture,75,"the Māori greeting ‘kia ora’","What can it function as?",["A greeting and expression of thanks","Only a place name","A number"],"A greeting and expression of thanks","New Zealand government language resources explain its common greeting uses.","en:culture-kiaora",source:("New Zealand History — 100 Māori words","https://nzhistory.govt.nz/culture/maori-language-week/100-maori-words")),
            c(.ash,.culture,80,"American Sign Language","Is it simply signed English?",["No, it has its own linguistic structure","Yes, always word-for-word","It is a written code"],"No, it has its own linguistic structure","NIDCD describes ASL as a complete natural language with properties distinct from English.","en:culture-asl",source:("NIDCD — American Sign Language","https://www.nidcd.nih.gov/health/american-sign-language"))
        ]
        let listening = [
            ("That sounds plausible, but not proven.","What distinction is made?",["Plausibility versus evidence","Cost versus speed","Past versus future"],"Plausibility versus evidence","Plausible is weaker than proven.","en:listen-plausible"),("I may have underestimated the deadline.","What happened?",["The deadline was tighter than expected","The task was cancelled","The date moved"],"The deadline was tighter than expected","Underestimate means judge as smaller or easier than reality.","en:listen-deadline"),("Could you walk me through that?","What is requested?",["A step-by-step explanation","A literal walk","A written apology"],"A step-by-step explanation","A natural request for guided explanation.","en:listen-walkthrough"),("The difference is subtle but important.","How large is the difference?",["Small but meaningful","Huge and obvious","Nonexistent"],"Small but meaningful","Subtle does not mean irrelevant.","en:listen-subtle"),("Let's leave that question open for now.","What is decided?",["Delay the conclusion","Reject the question","Answer immediately"],"Delay the conclusion","The issue remains unresolved without pressure.","en:listen-open")
        ].map { c(.ash,.listening,40,$0.0,$0.1,$0.2,$0.3,$0.4,$0.5) }
        let scenarios = [
            ("Could we clarify what success means here?","When is this useful?",["At the start of ambiguous work","When ordering lunch","After saying goodbye"],"At the start of ambiguous work","A professional but non-confrontational clarification.","en:scene-success"),("I need a moment to think about that.","What boundary does it set?",["More thinking time","A permanent refusal","A new deadline"],"More thinking time","A calm way not to answer immediately.","en:scene-moment"),("Would you mind sending that in writing?","What is requested?",["A written follow-up","A phone call","A refund"],"A written follow-up","Would you mind… softens the request.","en:scene-writing"),("I agree with the goal, but not the approach.","What is separated?",["Goal and method","Time and place","Fact and rumor"],"Goal and method","A precise way to disagree partially.","en:scene-approach"),("Can we revisit this tomorrow?","What is proposed?",["Postpone discussion","Cancel forever","Change the subject permanently"],"Postpone discussion","Revisit means return to the topic.","en:scene-revisit")
        ].map { c(.ash,.scenario,75,$0.0,$0.1,$0.2,$0.3,$0.4,$0.5) }
        let confusing = [
            ("affect / effect","Which is usually the verb meaning influence?",["affect","effect"],"affect","Affect is commonly the verb; effect is commonly the noun.","en:conf-affect-effect"),("historic / historical","Which suggests special importance in history?",["historic","historical"],"historic","Historical relates to history generally; historic often signals importance.","en:conf-historic"),("fewer / less","Which normally goes with countable items?",["fewer","less"],"fewer","Use fewer with countable plural nouns in careful usage.","en:conf-fewer"),("assure / ensure","Which means make certain that something happens?",["assure","ensure"],"ensure","Assure commonly reassures a person; ensure makes an outcome certain.","en:conf-assure"),("compliment / complement","Which means complete or enhance something?",["compliment","complement"],"complement","A compliment is praise; a complement completes or enhances.","en:conf-complement")
        ].map { c(.ash,.confusingWords,65,$0.0,$0.1,$0.2,$0.3,$0.4,$0.5) }
        let pictures = [
            ("An owl is guarding a mug labelled ‘temporary solution’.","Write a one-line caption.","Aim for natural tone; dry humor is optional.","en:picture-mug"),("Three sticky notes disagree about what ‘urgent’ means.","Describe or caption the scene.","One sentence is enough.","en:picture-notes"),("A laptop shows a success message while smoke rises behind it.","What would Ash say?","Respond to the meaning first; perfection is unnecessary.","en:picture-success"),("A tiny umbrella stands over a very large book.","Give the image a title.","Any concise title works.","en:picture-umbrella"),("Two clocks display different times and both look confident.","Write one sentence about them.","You may use apparently or somehow.","en:picture-clocks")
        ].map { c(.ash,.picturePrompt,75,$0.0,$0.1,[],"Open response",$0.2,$0.3,hook:"Ash presents an image with no unnecessary explanation.") }
        return expressions + dialogues + cultures + listening + scenarios + confusing + pictures
    }
}
