// Checks Marc's mail code on a real Mac: the IMAP and SMTP clients against ci/fake_mail_server.py,
// the parsers, and the learned triage on the sample history. Run from a folder where the fake server was started.
import Foundation

var failures = 0

func check(_ condition: Bool, _ label: String) {
    print(condition ? "PASS" : "FAIL", label)
    if !condition { failures += 1 }
}

// MARK: Parsing

let headerLiteral = "From: a@b.c\r\n"
let fetchLine = "* 3 FETCH (UID 103 FLAGS (\\Seen \\Flagged) INTERNALDATE \"17-Jul-2026 02:44:25 +0000\" BODY[HEADER.FIELDS (FROM SUBJECT)] {\(headerLiteral.utf8.count)}\r\n\(headerLiteral) BODY[]<0> NIL)"
let fetched = IMAPClient.parseFetch(Data(fetchLine.utf8))
check(fetched?.uid == 103, "FETCH: UID")
check(fetched?.flags == ["\\seen", "\\flagged"], "FETCH: flags")
check(fetched?.header.map { String(decoding: $0, as: UTF8.self) } == headerLiteral, "FETCH: literal inside a bracketed section")
check(fetched?.internalDate != nil, "FETCH: INTERNALDATE")
check(IMAPClient.sequenceSet([1, 2, 3, 5, 7, 8]) == "1:3,5,7:8", "UID sets")
check(IMAPClient.literalLength(Data("* LIST () \"/\" {42}".utf8)) == 42, "literal lengths")
check(IMAPClient.quote("a\"b\\c") == "\"a\\\"b\\\\c\"", "quoting")
check(MailParser.addresses("\"Becker, Tom\" <tom@acme.co>, sam@acme.co") == ["tom@acme.co", "sam@acme.co"], "address lists")
let unsubscribe = MailUnsubscribe.parse("<https://example.com/u>, <mailto:u@example.com>", post: "List-Unsubscribe=One-Click")
check(unsubscribe?.oneClick == true && unsubscribe?.mailto == "u@example.com", "List-Unsubscribe")
let encoded = MailEncoding.quotedPrintable("Café = good\n.dot\nline with trailing space ")
check(encoded.contains("Caf=C3=A9 =3D good") && encoded.contains("=2Edot") && encoded.hasSuffix("space=20"), "quoted-printable")
check(MailEncoding.header("Café ☕️").hasPrefix("=?utf-8?B?"), "encoded subject")
check(MailParser.decodeWords(MailEncoding.header("Café ☕️ and a fairly long subject that needs folding")) == "Café ☕️ and a fairly long subject that needs folding", "subject round trip")

// MARK: Learning

var learner = MailSamples.learner()
let set = learner.trainingSet()
let started = Date()
let trained = MailLearner.train(set)
print("Trained on \(set.labels.count) examples in \(String(format: "%.2f", Date().timeIntervalSince(started)))s, accuracy \(trained.accuracy.map { String(format: "%.2f", $0) } ?? "–")")
learner.adopt(trained.model, accuracy: trained.accuracy, examples: set.labels.count)
var lanes: [String: MailLane] = [:]
for message in MailSamples.inbox() {
    let traits = MailTriage.traits(of: message, myAddresses: ["you@elevenam.app", "you@icloud.com"])
    learner.observe(message, traits: traits)
    let verdict = learner.classify(message, traits: traits)
    lanes[message.id] = verdict.lane
    print("  \(message.fromName) → \(verdict.lane.title) (\(Int(verdict.confidence * 100))%) · \(verdict.reason)")
}
check(lanes["s1"] == .needsYou, "learned: Priya needs you")
check(lanes["s2"] == .needsYou, "learned: Tom needs you")
check(lanes["s5"] == .worthReading, "learned: Sam's notes are worth reading")
check(lanes["s7"] == .noise, "learned: Stripe receipts you never open are noise")
check(lanes["s11"] == .noise, "learned: Qantas offers are noise")
check(lanes["s12"] == .worthReading, "learned: Lenny's newsletter is worth reading")
check((trained.accuracy ?? 0) > 0.75, "learned: matches past behaviour")

let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
if let data = try? encoder.encode(learner), let restored = try? decoder.decode(MailLearner.self, from: data) {
    check(restored.records.count == learner.records.count && restored.examples == learner.examples, "learning survives a save")
    let priya = MailSamples.inbox()[0]
    let traits = MailTriage.traits(of: priya, myAddresses: ["you@elevenam.app"])
    check(restored.classify(priya, traits: traits).lane == .needsYou, "restored model decides the same")
} else {
    check(false, "learning survives a save")
}

// MARK: Protocols, against the fake server

var account = MailAccount.imap(provider: .other, name: "Test", address: "you@example.com")
account.imapHost = "127.0.0.1"
account.imapPort = 1143
account.imapSecurity = .plainForTesting
account.smtpHost = "127.0.0.1"
account.smtpPort = 1025
account.smtpSecurity = .plainForTesting

do {
    let folders = try await MailSync.test(account, credential: .password("secret"))
    check(folders.archive == "Archive" && folders.sent == "Sent Messages" && folders.trash == "Trash", "special-use folders (one sent as a literal)")
    account.archiveFolder = folders.archive
    account.trashFolder = folders.trash
    account.sentFolder = folders.sent

    let inbox = try await MailSync.inbox(account, credential: .password("secret"), haveBodies: [])
    check(inbox.messages.count == 3, "inbox: 3 messages")
    check(inbox.uidValidity == 42, "inbox: UIDVALIDITY")
    let tom = inbox.messages.first { $0.fromAddress == "tom@acme.co" }
    check(tom?.fromName == "Becker, Tom", "inbox: quoted display name")
    check(tom?.body.contains("Café at 3= good.") == true, "inbox: quoted-printable body")
    check(tom?.to.contains("sam@acme.co") == true, "inbox: To list with a comma in a name")
    let lenny = inbox.messages.first { $0.fromAddress == "lenny@substack.com" }
    check(lenny?.subject == "Pricing — part 2", "inbox: encoded subject")
    check(lenny?.isBulk == true && lenny?.unsubscribe?.oneClick == true, "inbox: list headers")
    check(inbox.messages.first { $0.fromAddress == "priya@northwind.vc" }?.seen == true, "inbox: seen flag")

    let history = try await MailSync.history(account, credential: .password("secret"), myAddresses: ["you@example.com"],
                                             skipping: Set(inbox.messages.map(\.messageID)))
    check(history.records.count == 4, "history: archive read for day-one learning (\(history.records.count))")
    check(history.records.filter(\.replied).count == 2, "history: answered flags")
    check(history.records.filter(\.ignored).count == 2, "history: unread for days")
    check(history.sentTo["priya@northwind.vc"] == 2 && history.sentTo["tom@acme.co"] == 1, "history: who you write to")

    try await MailSync.perform(.seen(true), uids: [102], validity: 42, account: account, credential: .password("secret"))
    try await MailSync.perform(.archive, uids: [103], validity: 42, account: account, credential: .password("secret"))
    let after = try await MailSync.inbox(account, credential: .password("secret"), haveBodies: [])
    check(after.messages.count == 2, "archive: left the inbox")
    check(after.messages.first { $0.uid == 102 }?.seen == true, "mark read: stored on the server")
    do {
        try await MailSync.perform(.archive, uids: [102], validity: 7, account: account, credential: .password("secret"))
        check(false, "a stale UIDVALIDITY is refused")
    } catch {
        check(true, "a stale UIDVALIDITY is refused")
    }

    let mail = OutgoingMail(fromName: "You Test", fromAddress: "you@example.com", to: ["Priya <priya@northwind.vc>"],
                            subject: "Re: Café", body: "Hi Priya,\n.starts with a dot\nThanks", inReplyTo: "<x@fake>", references: "<x@fake>")
    try await MailSync.send(mail, account: account, credential: .password("secret"), original: (uid: 102, validity: 42))
    let received = (try? String(contentsOfFile: "smtp-received.eml", encoding: .utf8)) ?? ""
    check(received.contains("In-Reply-To: <x@fake>"), "send: threading headers")
    check(received.contains("=2Estarts with a dot"), "send: a leading dot can't end the message")
    check(received.contains("Subject: =?utf-8?B?"), "send: encoded subject")
    let log = (try? String(contentsOfFile: "imap.log", encoding: .utf8)) ?? ""
    check(log.contains("APPEND \"Sent Messages\""), "send: copy filed in Sent")
    check(log.contains("UID STORE 102 +FLAGS.SILENT (\\Answered)"), "send: original marked answered")

    var wrong = account
    wrong.imapUsername = "someone@else.com"
    do {
        _ = try await MailSync.test(wrong, credential: .password("nope"))
        check(false, "a wrong password is reported")
    } catch {
        check(error.localizedDescription.contains("Sign-in failed"), "a wrong password is reported: \(error.localizedDescription)")
    }
} catch {
    check(false, "protocol run: \(error.localizedDescription)")
}

// MARK: Microsoft sign-in, against the fake token endpoint and Graph

MicrosoftAuth.authorityHost = "http://127.0.0.1:1080"
MicrosoftGraph.baseURL = "http://127.0.0.1:1080/v1.0"
let app = MicrosoftApp(clientID: "11111111-2222-3333-4444-555555555555", tenant: "common")
let pkce = MicrosoftAuth.PKCE.make()
check(pkce.verifier.count >= 43 && pkce.challenge != pkce.verifier && !pkce.challenge.contains("="), "Microsoft: PKCE verifier and S256 challenge")
let authorize = MicrosoftAuth.authorizeURL(app: app, pkce: pkce, loginHint: "you@example.com")?.absoluteString ?? ""
check(authorize.contains("code_challenge_method=S256") && authorize.contains("offline_access") && authorize.contains("IMAP.AccessAsUser.All")
      && authorize.contains("Mail.Send") && authorize.contains("redirect_uri=au.elevenam.sandbox://auth"), "Microsoft: authorize URL")
let callback = URL(string: "au.elevenam.sandbox://auth?code=code-1&state=\(pkce.state)")!
check((try? MicrosoftAuth.code(from: callback, state: pkce.state)) == "code-1", "Microsoft: code from the redirect")
check((try? MicrosoftAuth.code(from: callback, state: "someone-else")) == nil, "Microsoft: a redirect with the wrong state is refused")
let denied = URL(string: "au.elevenam.sandbox://auth?error=access_denied&error_description=The%20user%20declined&state=\(pkce.state)")!
do {
    _ = try MicrosoftAuth.code(from: denied, state: pkce.state)
    check(false, "Microsoft: a declined sign-in is reported")
} catch {
    check(error.localizedDescription.contains("declined"), "Microsoft: a declined sign-in is reported")
}

do {
    let tokens = try await MicrosoftAuth.redeem(code: "code-1", pkce: pkce, app: app)
    check(tokens.accessToken == "good-token" && tokens.refreshToken == "refresh-2", "Microsoft: code redeemed for tokens")
    check(tokens.expiresAt > Date().addingTimeInterval(3_000), "Microsoft: expiry read")
    let identity = MicrosoftAuth.identity(from: tokens.idToken)
    check(identity?.address == "you@example.com" && identity?.name == "You Test", "Microsoft: who signed in, from the ID token")
    let refreshed = try await MicrosoftAuth.refresh("refresh-1", app: app, scope: MicrosoftAuth.graphSendScope)
    check(refreshed.accessToken == "good-token", "Microsoft: refresh token gives a new access token")
    do {
        _ = try await MicrosoftAuth.refresh("expired", app: app, scope: MicrosoftAuth.imapScope)
        check(false, "Microsoft: a dead refresh token is reported")
    } catch {
        check(error.localizedDescription.contains("AADSTS70000") && !error.localizedDescription.contains("Trace ID"), "Microsoft: a dead refresh token is reported: \(error.localizedDescription)")
    }
    do {
        _ = try await MicrosoftAuth.refresh("refresh-1", app: MicrosoftApp(clientID: "wrong"), scope: MicrosoftAuth.imapScope)
        check(false, "Microsoft: an unknown client ID is reported")
    } catch {
        check(error.localizedDescription.contains("AADSTS700016"), "Microsoft: an unknown client ID is reported")
    }

    var outlook = account
    outlook.provider = .outlook
    outlook.microsoft = app
    outlook.saveSentCopy = false
    let folders = try await MailSync.test(outlook, credential: .token(tokens.accessToken))
    check(folders.archive == "Archive", "Microsoft: IMAP sign-in with the token (XOAUTH2)")
    let inbox = try await MailSync.inbox(outlook, credential: .token("good-token"), haveBodies: [])
    check(!inbox.messages.isEmpty, "Microsoft: inbox read with the token")
    do {
        _ = try await MailSync.test(outlook, credential: .token("stale"))
        check(false, "Microsoft: a refused token is reported")
    } catch {
        check(error.localizedDescription.contains("Sign-in was refused"), "Microsoft: a refused token is reported")
    }

    let mail = OutgoingMail(fromName: "You Test", fromAddress: "you@example.com", to: ["priya@northwind.vc"],
                            subject: "Sent through Graph", body: "Hello from 11am")
    try await MailSync.send(mail, account: outlook, credential: .token("good-token"), original: (uid: 102, validity: 42), graphToken: "good-token")
    let graphSent = (try? String(contentsOfFile: "graph-sent.eml", encoding: .utf8)) ?? ""
    check(graphSent.contains("Subject: Sent through Graph") && graphSent.contains("Hello from 11am"), "Microsoft: sent through Graph as MIME")
    do {
        try await MicrosoftGraph.send(mail, token: "stale")
        check(false, "Microsoft: Graph refusal is reported")
    } catch {
        check(error.localizedDescription.contains("Access token is empty"), "Microsoft: Graph refusal is reported")
    }
    do {
        try await MailSync.send(mail, account: outlook, credential: .token("good-token"), original: nil, graphToken: nil)
        check(false, "Microsoft: never falls back to SMTP without a password")
    } catch {
        check(true, "Microsoft: never falls back to SMTP without a password")
    }
} catch {
    check(false, "Microsoft run: \(error.localizedDescription)")
}

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
