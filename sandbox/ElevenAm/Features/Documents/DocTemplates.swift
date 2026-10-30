import Foundation

/// Starting points for Write. Plain Markdown with the parts to fill in marked in brackets.
struct DocTemplate: Identifiable, Sendable {
    let id: String
    let name: String
    let symbol: String
    let markdown: String

    static func today() -> String {
        Date().formatted(.dateTime.day().month(.wide).year())
    }

    static let all: [DocTemplate] = [
        DocTemplate(id: "letter", name: "Letter", symbol: "envelope", markdown: """
        [Your name]
        [Street address]
        [Suburb, State, Postcode]

        \(today())

        [Their name]
        [Their organisation]
        [Their address]

        Dear [name],

        [Why you're writing, in one sentence.]

        [The details: what happened, what you need, by when.]

        [What happens next.]

        Kind regards,

        [Your name]
        """),
        DocTemplate(id: "proposal", name: "Proposal", symbol: "doc.richtext", markdown: """
        # Proposal: [project] for [client]

        Prepared for [name], [organisation] · \(today())

        ## The problem

        [What's in the way today, in their words.]

        ## What we'll do

        1. [First outcome]
        2. [Second outcome]
        3. [Third outcome]

        ## Timeline

        | Phase | What you get | When |
        | --- | --- | --- |
        | Discovery | [Findings and a plan] | Week 1 |
        | Build | [The thing] | Weeks 2–5 |
        | Launch | [Live, with training] | Week 6 |

        ## Investment

        | Item | Price |
        | --- | ---: |
        | [Item] | $[0] |
        | **Total (ex GST)** | **$[0]** |

        > [!NOTE] Valid for 30 days
        > Prices exclude GST. 50% on acceptance, 50% on launch.

        ## Next step

        Reply to accept, or book a call: [link].
        """),
        DocTemplate(id: "onepager", name: "One-pager", symbol: "doc.text", markdown: """
        # [Company or product]

        **[One sentence: what it is and who it's for.]**

        ## The problem
        [Two or three sentences.]

        ## The solution
        [Two or three sentences.]

        ## Why now
        - [Change in the world]
        - [Proof it's working]

        ## Traction
        | Measure | Today |
        | --- | ---: |
        | Customers | [0] |
        | Monthly revenue | $[0] |

        ## The ask
        [What you want from the reader.]

        [Name] · [email] · [phone]
        """),
        DocTemplate(id: "meeting", name: "Meeting notes", symbol: "person.2", markdown: """
        # [Meeting] · \(today())

        **Who:** [names]
        **Goal:** [what this meeting is for]

        ## Notes
        - [Point]

        ## Decisions
        - [Decision]

        ## Actions
        - [ ] [Action] — [owner], [when]
        - [ ] [Action] — [owner], [when]
        """),
        DocTemplate(id: "report", name: "Report", symbol: "chart.bar.doc.horizontal", markdown: """
        # [Report title]

        [Author] · \(today())

        ## Summary
        [The three things the reader must know, in plain sentences.]

        ## Background
        [Why this report exists.]

        ## Findings
        ### [Finding one]
        [Detail and evidence.]

        ### [Finding two]
        [Detail and evidence.]

        ## Recommendations
        1. [Recommendation]
        2. [Recommendation]

        ## Appendix
        [Data, sources, methods.]
        """),
        DocTemplate(id: "resume", name: "Résumé", symbol: "person.text.rectangle", markdown: """
        # [Your name]

        [City] · [email] · [phone] · [linkedin.com/in/you]

        [Two sentences on what you do best and what you're looking for.]

        ## Experience

        ### [Role] · [Company]
        *[Start] – [End]*
        - [Achievement with a number]
        - [Achievement with a number]

        ### [Role] · [Company]
        *[Start] – [End]*
        - [Achievement with a number]

        ## Education
        **[Degree]**, [Institution], [Year]

        ## Skills
        [Skill] · [Skill] · [Skill]
        """),
        DocTemplate(id: "press", name: "Press release", symbol: "megaphone", markdown: """
        **FOR IMMEDIATE RELEASE**

        # [Headline: what happened, in under ten words]

        ### [Subhead with the most important detail]

        **[City], \(today())** — [Opening paragraph: who, what, when, where, why.]

        [Second paragraph: the detail that makes it matter.]

        > "[Quote from a founder or customer.]" — [Name], [Title]

        [Closing paragraph: availability, pricing, what's next.]

        ## About [Company]
        [Two sentences.]

        **Media contact:** [name] · [email] · [phone]

        *Ends*
        """),
    ]
}
