import Foundation

// Sport structure
struct SportInfo {
    var teams: [String]?
    var notableEntities: [String]?
    var notableTournaments: [String]?
    var notableTeams: [String]?
}

struct Sports {
    static let shared = Sports()

    let Football = SportInfo(teams: ["Real Madrid", "Barcelona", "Manchester United", "Liverpool", "Bayern Munich", "Paris Saint-Germain"])
    let Basketball = SportInfo(teams: ["Los Angeles Lakers", "Golden State Warriors", "Chicago Bulls", "Boston Celtics"])
    let AmericanFootball = SportInfo(teams: ["New England Patriots", "Dallas Cowboys", "Green Bay Packers"])
    let Baseball = SportInfo(teams: ["New York Yankees", "Boston Red Sox", "Los Angeles Dodgers"])
    let Cricket = SportInfo(teams: ["India", "Australia", "England", "New Zealand"])
    let Rugby = SportInfo(teams: ["New Zealand All Blacks", "South Africa Springboks", "England"])
    let Tennis = SportInfo(notableEntities: ["Wimbledon", "US Open", "French Open", "Australian Open"])
    let Golf = SportInfo(notableTournaments: ["The Masters", "The Open Championship", "PGA Championship"])
    let Formula1 = SportInfo(teams: ["Mercedes", "Ferrari", "Red Bull Racing"])
    let IceHockey = SportInfo(teams: ["Montreal Canadiens", "Toronto Maple Leafs", "New York Rangers"])
    let Volleyball = SportInfo(notableTeams: ["Brazil", "USA", "Italy"])
    let Handball = SportInfo(notableTeams: ["Denmark", "France", "Spain"])
    let TableTennis = SportInfo(notableTeams: ["China", "Japan", "Germany"])
}

// Topics structure
struct TopicInfo {
    var subtopics: [String]?
    var connectedTo: [String]?
    var relatedTo: [String]?
    var crossReferences: [String]?
}

struct LeisureInfo {
    var subtopics: [String]?
    var relatedTo: [String]?
    var sports: Sports
}

struct Topics {
    static let shared = Topics()

    let `Self` = TopicInfo(subtopics: ["Family", "Relationships", "Health", "Hobbies"],
                           connectedTo: ["Psychology", "Career", "Education"])

    let Career = TopicInfo(subtopics: ["Growth", "Dynamics", "Trends"],
                           relatedTo: ["Business", "Education", "Technology"])

    let Society = TopicInfo(subtopics: ["Politics", "Issues", "Traditions", "Media", "Entertainment"],
                            connectedTo: ["Events", "Philosophy", "Arts"])

    let Education = TopicInfo(subtopics: ["Academics", "Skills", "Growth"],
                              relatedTo: ["Science", "Technology", "Career"])

    let Technology = TopicInfo(subtopics: ["Innovations", "AI", "Environment", "Space", "Medicine"],
                               crossReferences: ["Events", "Education", "Ethics"])

    let Economics = TopicInfo(subtopics: ["Finance", "Economy", "Business"],
                              connectedTo: ["Events", "Career"])

    let Leisure = LeisureInfo(subtopics: ["Travel", "Entertainment", "Food"],
                              relatedTo: ["Health", "Culture", "Self"],
                              sports: Sports.shared)

    let Philosophy = TopicInfo(subtopics: ["Morality", "Existence", "Beliefs", "Values"],
                               connectedTo: ["Religion", "Science", "Psychology"])

    let Events = TopicInfo(subtopics: ["News", "Conflicts", "Discoveries"],
                           relatedTo: ["Politics", "Science", "Society"])

    let Psychology = TopicInfo(subtopics: ["Emotions", "Cognition", "Mental-health"],
                               connectedTo: ["Self", "Relationships", "Health"])

    let Future = TopicInfo(subtopics: ["Goals", "Trends", "Progress"],
                           relatedTo: ["Technology", "Society", "Self"])
}
