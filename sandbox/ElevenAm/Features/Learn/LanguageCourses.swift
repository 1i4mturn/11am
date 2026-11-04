import Foundation

// The written units that ship with 11am: the start of Spanish and French. Later units, and other languages,
// are written by Harris as you reach them (and checked before they're used).

private func w(_ term: String, _ meaning: String, _ symbol: String? = nil) -> VocabItem {
    VocabItem(term: term, meaning: meaning, symbol: symbol)
}

private func s(_ target: String, _ english: String, _ alternatives: String...) -> Sentence {
    Sentence(target: target, english: english, alternatives: alternatives)
}

private func q(_ level: CEFR, _ prompt: String, _ english: String, _ options: [String], _ answer: Int) -> PlacementQuestion {
    PlacementQuestion(level: level, prompt: prompt, english: english, options: options, answer: answer)
}

enum LanguageCourses {
    static func course(_ language: LanguageInfo) -> Course {
        switch language.code {
        case "es": return spanish
        case "fr": return french
        default: return Course(language: language.id, units: [], placement: [])
        }
    }

    static let spanish = Course(language: "es-ES", units: [
        CourseUnit(id: "es-a1-1", level: .a1, title: "Hello",
                   tip: "Spanish questions start with an upside-down question mark and end with a normal one: ¿Qué tal?",
                   words: [
                       w("hola", "hello", "hand.wave"), w("adiós", "goodbye", "figure.walk"), w("gracias", "thank you", "heart"),
                       w("por favor", "please", "hands.sparkles"), w("sí", "yes", "checkmark"), w("no", "no", "xmark"),
                       w("buenos días", "good morning", "sun.max"), w("buenas noches", "good night", "moon.stars"),
                       w("¿qué tal?", "how are you?", "face.smiling"), w("me llamo", "my name is", "person.text.rectangle"),
                   ],
                   sentences: [
                       s("Hola, me llamo Ana.", "Hello, my name is Ana.", "Hi, my name is Ana.", "Hello, I'm Ana."),
                       s("Buenos días, ¿qué tal?", "Good morning, how are you?"),
                       s("Gracias, adiós.", "Thank you, goodbye.", "Thanks, goodbye."),
                       s("Sí, por favor.", "Yes, please."),
                       s("No, gracias.", "No, thank you.", "No, thanks."),
                       s("Buenas noches, Ana.", "Good night, Ana."),
                       s("Hola, ¿qué tal?", "Hello, how are you?", "Hi, how are you?"),
                       s("Me llamo Tom, gracias.", "My name is Tom, thank you.", "My name is Tom, thanks."),
                   ]),
        CourseUnit(id: "es-a1-2", level: .a1, title: "At the café",
                   tip: "Every noun is masculine or feminine: el café, la leche. Un and una both mean “a”.",
                   words: [
                       w("el café", "the coffee", "cup.and.saucer"), w("el agua", "the water", "drop"), w("el pan", "the bread", "birthday.cake"),
                       w("la leche", "the milk", "waterbottle"), w("el té", "the tea", "mug"), w("la cuenta", "the bill", "doc.text"),
                       w("quiero", "I want", "hand.point.up"), w("un", "a (masculine)"), w("y", "and"), w("con", "with"),
                   ],
                   sentences: [
                       s("Quiero un café.", "I want a coffee.", "I'd like a coffee."),
                       s("Un té con leche, por favor.", "A tea with milk, please."),
                       s("Quiero agua y pan.", "I want water and bread.", "I'd like water and bread."),
                       s("La cuenta, por favor.", "The bill, please.", "The check, please."),
                       s("Un café con leche.", "A coffee with milk.", "A white coffee."),
                       s("Quiero pan, por favor.", "I want bread, please.", "I'd like bread, please."),
                       s("Agua, por favor.", "Water, please."),
                       s("Quiero un té y un café.", "I want a tea and a coffee.", "I'd like a tea and a coffee."),
                   ]),
        CourseUnit(id: "es-a1-3", level: .a1, title: "Family",
                   tip: "Mi means “my” for one thing (mi madre); for more than one it's mis (mis hermanos).",
                   words: [
                       w("la madre", "the mother", "figure.and.child.holdinghands"), w("el padre", "the father", "figure.stand"),
                       w("el hermano", "the brother", "person"), w("la hermana", "the sister", "person.fill"),
                       w("el amigo", "the friend (man)", "person.2"), w("la amiga", "the friend (woman)", "person.2.fill"),
                       w("mi", "my"), w("es", "is"), w("tengo", "I have", "hand.raised"), w("el hijo", "the son", "figure.child"),
                   ],
                   sentences: [
                       s("Mi madre es Ana.", "My mother is Ana."),
                       s("Tengo un hermano.", "I have a brother.", "I've got a brother."),
                       s("Tengo una hermana y un hermano.", "I have a sister and a brother.", "I've got a sister and a brother."),
                       s("Es mi amigo.", "He is my friend.", "He's my friend."),
                       s("Es mi madre.", "She is my mother.", "She's my mother."),
                       s("Mi padre es Tom.", "My father is Tom.", "My dad is Tom."),
                       s("Tengo un hijo.", "I have a son.", "I've got a son."),
                       s("Mi amiga es Ana.", "My friend is Ana."),
                   ]),
        CourseUnit(id: "es-a1-4", level: .a1, title: "Around town",
                   tip: "Use está for where something is: ¿Dónde está el museo? El museo está aquí.",
                   words: [
                       w("la calle", "the street", "road.lanes"), w("el banco", "the bank", "building.columns"),
                       w("la estación", "the station", "tram"), w("el hotel", "the hotel", "bed.double"), w("el museo", "the museum", "photo.artframe"),
                       w("dónde", "where", "mappin.and.ellipse"), w("está", "is (where)"), w("aquí", "here", "location"),
                       w("allí", "there", "arrow.up.right"), w("cerca", "near", "scope"),
                   ],
                   sentences: [
                       s("¿Dónde está el hotel?", "Where is the hotel?", "Where's the hotel?"),
                       s("El banco está aquí.", "The bank is here.", "The bank's here."),
                       s("La estación está cerca.", "The station is near.", "The station is nearby.", "The station is close."),
                       s("El museo está allí.", "The museum is there.", "The museum is over there."),
                       s("¿Dónde está la estación?", "Where is the station?", "Where's the station?"),
                       s("El hotel está cerca.", "The hotel is near.", "The hotel is nearby.", "The hotel is close."),
                       s("¿Dónde está el banco?", "Where is the bank?", "Where's the bank?"),
                       s("La calle está aquí.", "The street is here."),
                   ]),
        CourseUnit(id: "es-a1-5", level: .a1, title: "Days and plans",
                   tip: "Days of the week take el: el lunes means “on Monday”. Voy a means “I go to”, and a + el becomes al: voy al museo.",
                   words: [
                       w("hoy", "today", "calendar"), w("mañana", "tomorrow", "calendar.badge.clock"), w("el lunes", "Monday", "1.circle"),
                       w("el sábado", "Saturday", "6.circle"), w("trabajo", "I work", "briefcase"), w("voy", "I go", "figure.walk"),
                       w("a", "to"), w("la playa", "the beach", "beach.umbrella"), w("la semana", "the week", "calendar.day.timeline.left"),
                       w("el fin de semana", "the weekend", "sun.haze"),
                   ],
                   sentences: [
                       s("Hoy trabajo.", "Today I work.", "I work today.", "I'm working today."),
                       s("Mañana voy a la playa.", "Tomorrow I go to the beach.", "Tomorrow I'm going to the beach."),
                       s("El lunes trabajo.", "On Monday I work.", "I work on Monday."),
                       s("El sábado voy a Madrid.", "On Saturday I go to Madrid.", "On Saturday I'm going to Madrid."),
                       s("Voy a la playa el fin de semana.", "I go to the beach at the weekend.", "I'm going to the beach at the weekend.", "I go to the beach on the weekend."),
                       s("Hoy no trabajo.", "Today I don't work.", "I don't work today.", "I'm not working today."),
                       s("Mañana trabajo con Ana.", "Tomorrow I work with Ana.", "I work with Ana tomorrow."),
                       s("Voy al museo hoy.", "I go to the museum today.", "I'm going to the museum today."),
                   ],
                   story: Story(title: "Un sábado en Madrid", lines: [
                       s("Hola, me llamo Ana.", "Hello, my name is Ana."),
                       s("Hoy es sábado y no trabajo.", "Today is Saturday and I don't work."),
                       s("Voy a un café con mi amiga.", "I go to a café with my friend."),
                       s("Quiero un café con leche y pan.", "I want a coffee with milk and bread."),
                       s("Después vamos al museo. Está cerca.", "Afterwards we go to the museum. It's near."),
                       s("Mañana voy a la playa con mi hermano.", "Tomorrow I go to the beach with my brother."),
                   ], questions: [
                       StoryQuestion(question: "What day is it?", options: ["Monday", "Saturday", "Sunday"], answer: 1),
                       StoryQuestion(question: "What does Ana order?", options: ["Tea with milk", "Water and bread", "A white coffee and bread"], answer: 2),
                       StoryQuestion(question: "Who goes to the beach tomorrow?", options: ["Ana and her brother", "Ana and her mother", "Ana's friend"], answer: 0),
                   ])),
    ], placement: [
        q(.a1, "Buenos ___, ¿qué tal?", "Good morning, how are you?", ["días", "noches", "gracias", "tal"], 0),
        q(.a1, "Quiero ___ café, por favor.", "I want a coffee, please.", ["un", "una", "el", "los"], 0),
        q(.a1, "¿Dónde ___ el hotel?", "Where is the hotel?", ["está", "es", "son", "estoy"], 0),
        q(.a1, "Tengo dos ___.", "I have two brothers.", ["hermanos", "hermano", "hermana", "hermanas"], 0),
        q(.a2, "Ayer ___ al cine con Ana.", "Yesterday I went to the cinema with Ana.", ["fui", "voy", "iré", "iba"], 0),
        q(.a2, "Cuando era niño, ___ en Sevilla.", "When I was a child, I lived in Seville.", ["vivía", "viví", "vivo", "viviré"], 0),
        q(.a2, "¿Has ___ la película?", "Have you seen the film?", ["visto", "ver", "veía", "vi"], 0),
        q(.a2, "Me gustan ___ manzanas.", "I like apples.", ["las", "los", "la", "el"], 0),
        q(.b1, "Si tuviera tiempo, ___ más.", "If I had time, I would read more.", ["leería", "leo", "leí", "leeré"], 0),
        q(.b1, "Espero que ___ bien.", "I hope you're well.", ["estés", "estás", "estabas", "estarás"], 0),
        q(.b1, "Llevo dos años ___ español.", "I've been learning Spanish for two years.", ["aprendiendo", "aprendo", "aprendido", "aprender"], 0),
        q(.b1, "No creo que ___ razón.", "I don't think he's right.", ["tenga", "tiene", "tenía", "tendrá"], 0),
        q(.b2, "Me alegro de que ___ venido.", "I'm glad you came.", ["hayas", "has", "habías", "habrás"], 0),
        q(.b2, "Si lo hubiera sabido, te lo ___ dicho.", "If I'd known, I'd have told you.", ["habría", "había", "he", "habré"], 0),
        q(.b2, "Por mucho que ___, no lo entiende.", "However much he studies, he doesn't understand it.", ["estudie", "estudia", "estudió", "estudiará"], 0),
        q(.b2, "Se lo dije para que lo ___.", "I told him so that he would know.", ["supiera", "sabe", "sabía", "sabrá"], 0),
    ])

    static let french = Course(language: "fr-FR", units: [
        CourseUnit(id: "fr-a1-1", level: .a1, title: "Hello",
                   tip: "French puts a space before ? and ! — Ça va ? — and vous is the polite “you”.",
                   words: [
                       w("bonjour", "hello", "hand.wave"), w("au revoir", "goodbye", "figure.walk"), w("merci", "thank you", "heart"),
                       w("s'il vous plaît", "please", "hands.sparkles"), w("oui", "yes", "checkmark"), w("non", "no", "xmark"),
                       w("bonsoir", "good evening", "moon.stars"), w("ça va ?", "how are you?", "face.smiling"),
                       w("je m'appelle", "my name is", "person.text.rectangle"), w("salut", "hi", "hand.raised"),
                   ],
                   sentences: [
                       s("Bonjour, je m'appelle Claire.", "Hello, my name is Claire.", "Hi, my name is Claire.", "Hello, I'm Claire."),
                       s("Salut, ça va ?", "Hi, how are you?", "Hi, how's it going?"),
                       s("Merci, au revoir.", "Thank you, goodbye.", "Thanks, goodbye."),
                       s("Oui, s'il vous plaît.", "Yes, please."),
                       s("Non, merci.", "No, thank you.", "No, thanks."),
                       s("Bonsoir, Claire.", "Good evening, Claire."),
                       s("Bonjour, ça va ?", "Hello, how are you?"),
                       s("Je m'appelle Tom, merci.", "My name is Tom, thank you.", "My name is Tom, thanks."),
                   ]),
        CourseUnit(id: "fr-a1-2", level: .a1, title: "At the café",
                   tip: "Du, de la and de l' mean “some”: du pain, de la confiture, de l'eau. Je voudrais is the polite “I'd like”.",
                   words: [
                       w("un café", "a coffee", "cup.and.saucer"), w("de l'eau", "some water", "drop"), w("du pain", "some bread", "birthday.cake"),
                       w("du lait", "some milk", "waterbottle"), w("un thé", "a tea", "mug"), w("l'addition", "the bill", "doc.text"),
                       w("je voudrais", "I would like", "hand.point.up"), w("et", "and"), w("avec", "with"), w("un croissant", "a croissant", "moon"),
                   ],
                   sentences: [
                       s("Je voudrais un café.", "I would like a coffee.", "I'd like a coffee."),
                       s("Un thé avec du lait, s'il vous plaît.", "A tea with milk, please."),
                       s("Je voudrais de l'eau et du pain.", "I would like water and bread.", "I'd like some water and some bread.", "I'd like water and bread."),
                       s("L'addition, s'il vous plaît.", "The bill, please.", "The check, please."),
                       s("Un café et un croissant.", "A coffee and a croissant."),
                       s("Je voudrais du pain, s'il vous plaît.", "I would like some bread, please.", "I'd like some bread, please.", "I'd like bread, please."),
                       s("De l'eau, s'il vous plaît.", "Some water, please.", "Water, please."),
                       s("Je voudrais un thé et un café.", "I would like a tea and a coffee.", "I'd like a tea and a coffee."),
                   ]),
        CourseUnit(id: "fr-a1-3", level: .a1, title: "Family",
                   tip: "My is mon before masculine words (mon père) and ma before feminine ones (ma mère).",
                   words: [
                       w("la mère", "the mother", "figure.and.child.holdinghands"), w("le père", "the father", "figure.stand"),
                       w("le frère", "the brother", "person"), w("la sœur", "the sister", "person.fill"),
                       w("l'ami", "the friend (man)", "person.2"), w("l'amie", "the friend (woman)", "person.2.fill"),
                       w("mon", "my (masculine)"), w("ma", "my (feminine)"), w("j'ai", "I have", "hand.raised"), w("c'est", "this is, it's"),
                   ],
                   sentences: [
                       s("C'est ma mère.", "This is my mother.", "It's my mother.", "She's my mother."),
                       s("J'ai un frère.", "I have a brother.", "I've got a brother."),
                       s("J'ai une sœur et un frère.", "I have a sister and a brother.", "I've got a sister and a brother."),
                       s("C'est mon ami.", "This is my friend.", "He's my friend.", "It's my friend."),
                       s("C'est mon père.", "This is my father.", "It's my father.", "He's my father.", "This is my dad."),
                       s("Ma sœur s'appelle Claire.", "My sister is called Claire.", "My sister's name is Claire."),
                       s("J'ai une amie.", "I have a friend.", "I've got a friend."),
                       s("C'est mon frère et ma sœur.", "This is my brother and my sister.", "These are my brother and my sister."),
                   ]),
        CourseUnit(id: "fr-a1-4", level: .a1, title: "Around town",
                   tip: "Où est… ? asks where one thing is. À côté de means “next to”.",
                   words: [
                       w("la rue", "the street", "road.lanes"), w("la banque", "the bank", "building.columns"), w("la gare", "the station", "tram"),
                       w("l'hôtel", "the hotel", "bed.double"), w("le musée", "the museum", "photo.artframe"), w("où", "where", "mappin.and.ellipse"),
                       w("est", "is"), w("ici", "here", "location"), w("là-bas", "over there", "arrow.up.right"), w("près", "near", "scope"),
                   ],
                   sentences: [
                       s("Où est l'hôtel ?", "Where is the hotel?", "Where's the hotel?"),
                       s("La banque est ici.", "The bank is here.", "The bank's here."),
                       s("La gare est près.", "The station is near.", "The station is nearby.", "The station is close."),
                       s("Le musée est là-bas.", "The museum is over there.", "The museum is there."),
                       s("Où est la gare ?", "Where is the station?", "Where's the station?"),
                       s("L'hôtel est ici.", "The hotel is here."),
                       s("Où est la banque ?", "Where is the bank?", "Where's the bank?"),
                       s("La rue est là-bas.", "The street is over there.", "The street is there."),
                   ]),
        CourseUnit(id: "fr-a1-5", level: .a1, title: "Days and plans",
                   tip: "Je vais à means “I'm going to”; à + le becomes au: je vais au musée.",
                   words: [
                       w("aujourd'hui", "today", "calendar"), w("demain", "tomorrow", "calendar.badge.clock"), w("lundi", "Monday", "1.circle"),
                       w("samedi", "Saturday", "6.circle"), w("je travaille", "I work", "briefcase"), w("je vais", "I go", "figure.walk"),
                       w("à", "to"), w("la plage", "the beach", "beach.umbrella"), w("la semaine", "the week", "calendar.day.timeline.left"),
                       w("le week-end", "the weekend", "sun.haze"),
                   ],
                   sentences: [
                       s("Aujourd'hui je travaille.", "Today I work.", "I work today.", "I'm working today."),
                       s("Demain je vais à la plage.", "Tomorrow I go to the beach.", "Tomorrow I'm going to the beach."),
                       s("Lundi je travaille.", "On Monday I work.", "I work on Monday."),
                       s("Samedi je vais à Paris.", "On Saturday I go to Paris.", "On Saturday I'm going to Paris."),
                       s("Je vais à la plage le week-end.", "I go to the beach at the weekend.", "I go to the beach on the weekend."),
                       s("Aujourd'hui je ne travaille pas.", "Today I don't work.", "I don't work today.", "I'm not working today."),
                       s("Demain je travaille avec Claire.", "Tomorrow I work with Claire.", "I work with Claire tomorrow."),
                       s("Je vais au musée aujourd'hui.", "I go to the museum today.", "I'm going to the museum today."),
                   ],
                   story: Story(title: "Un samedi à Paris", lines: [
                       s("Bonjour, je m'appelle Claire.", "Hello, my name is Claire."),
                       s("Aujourd'hui c'est samedi et je ne travaille pas.", "Today is Saturday and I'm not working."),
                       s("Je vais au café avec mon amie.", "I go to the café with my friend."),
                       s("Je voudrais un café et un croissant.", "I'd like a coffee and a croissant."),
                       s("Après, nous allons au musée. Il est près.", "Afterwards we go to the museum. It's near."),
                       s("Demain je vais à la plage avec mon frère.", "Tomorrow I'm going to the beach with my brother."),
                   ], questions: [
                       StoryQuestion(question: "What day is it?", options: ["Monday", "Saturday", "Sunday"], answer: 1),
                       StoryQuestion(question: "What does Claire order?", options: ["A tea with milk", "A coffee and a croissant", "Water and bread"], answer: 1),
                       StoryQuestion(question: "Who goes to the beach tomorrow?", options: ["Claire's friend", "Claire and her mother", "Claire and her brother"], answer: 2),
                   ])),
    ], placement: [
        q(.a1, "Bonjour, je m'___ Claire.", "Hello, my name is Claire.", ["appelle", "appelles", "appeler", "appelé"], 0),
        q(.a1, "Je voudrais ___ café.", "I'd like a coffee.", ["un", "une", "le", "des"], 0),
        q(.a1, "Où ___ la gare ?", "Where is the station?", ["est", "es", "sont", "suis"], 0),
        q(.a1, "C'est ___ mère.", "This is my mother.", ["ma", "mon", "mes", "me"], 0),
        q(.a2, "Hier, je ___ allé au cinéma.", "Yesterday I went to the cinema.", ["suis", "ai", "vais", "étais"], 0),
        q(.a2, "Quand j'étais petit, je ___ à Lyon.", "When I was little, I lived in Lyon.", ["vivais", "vis", "ai vécu", "vivrai"], 0),
        q(.a2, "Tu ___ déjà vu ce film ?", "Have you already seen this film?", ["as", "es", "avais", "auras"], 0),
        q(.a2, "J'aime ___ pommes.", "I like apples.", ["les", "la", "le", "des"], 0),
        q(.b1, "Si j'avais le temps, je ___ plus.", "If I had time, I'd read more.", ["lirais", "lis", "lirai", "lisais"], 0),
        q(.b1, "Il faut que tu ___ patient.", "You need to be patient.", ["sois", "es", "seras", "étais"], 0),
        q(.b1, "J'apprends le français ___ deux ans.", "I've been learning French for two years.", ["depuis", "pendant", "il y a", "dans"], 0),
        q(.b1, "Je ne pense pas qu'il ___ raison.", "I don't think he's right.", ["ait", "a", "avait", "aura"], 0),
        q(.b2, "Je suis content que tu ___ venu.", "I'm glad you came.", ["sois", "es", "étais", "seras"], 0),
        q(.b2, "Si je l'avais su, je te l'___ dit.", "If I'd known, I'd have told you.", ["aurais", "avais", "ai", "aurai"], 0),
        q(.b2, "Bien qu'il ___ beaucoup, il ne comprend pas.", "Although he studies a lot, he doesn't understand.", ["étudie", "étudies", "étudiait", "étudiera"], 0),
        q(.b2, "Je le lui ai dit pour qu'il le ___.", "I told him so that he would know.", ["sache", "sait", "savait", "saura"], 0),
    ])
}
