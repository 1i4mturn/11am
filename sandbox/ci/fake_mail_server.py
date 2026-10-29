#!/usr/bin/env python3
"""A tiny IMAP and SMTP server for 11am's mail protocol tests. Plain TCP on localhost, one fake account.

IMAP on 127.0.0.1:1143, SMTP on 127.0.0.1:1025, a Microsoft token endpoint and Graph sendMail on 127.0.0.1:1080.
Login: you@example.com / secret, or XOAUTH2 with the token "good-token".
Messages sent over SMTP are written to ./smtp-received.eml; IMAP commands are logged to ./imap.log.
"""
import base64
import email.utils
import http.server
import json
import re
import socketserver
import sys
import threading
import time
import urllib.parse

USER, PASSWORD = "you@example.com", "secret"
LOG = open("imap.log", "w", buffering=1)


def message(sender, to, subject, body, days_ago=0, extra=""):
    date = email.utils.formatdate(time.time() - days_ago * 86400, localtime=False)
    headers = (
        f"From: {sender}\r\nTo: {to}\r\nSubject: {subject}\r\nDate: {date}\r\n"
        f"Message-ID: <{abs(hash((sender, subject, days_ago)))}@fake>\r\n{extra}"
        "MIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\n"
    )
    return headers + "\r\n" + body


def build():
    inbox = [
        (101, {"\\Seen"}, message("Priya Shah <priya@northwind.vc>", "you@example.com", "Quick question on the round",
                                  "Could you confirm how much of the round is committed?\r\n", 1)),
        (102, set(), message("Lenny <lenny@substack.com>", "you@example.com", "=?utf-8?B?UHJpY2luZyDigJQgcGFydCAy?=",
                             "This week: pricing.\r\n", 0,
                             "List-Unsubscribe: <https://example.com/u>, <mailto:u@example.com>\r\nList-Unsubscribe-Post: List-Unsubscribe=One-Click\r\n")),
        (103, set(), message("\"Becker, Tom\" <tom@acme.co>", "you@example.com, \"Sam, O\" <sam@acme.co>", "Deck by Friday",
                             "Can you send the deck by Friday?\r\n", 0, "Content-Transfer-Encoding: quoted-printable\r\n").replace(
            "Can you send the deck by Friday?", "Can you send the deck by Friday? Caf=C3=A9 at 3=3D good.")),
    ]
    archive = [
        (11, {"\\Seen", "\\Answered"}, message("priya@northwind.vc", "you@example.com", "Earlier", "Thanks!\r\n", 40)),
        (12, {"\\Seen", "\\Answered"}, message("priya@northwind.vc", "you@example.com", "Earlier 2", "Thanks!\r\n", 50)),
        (13, set(), message("offers@qantas.com.au", "you@example.com", "20% off", "Sale\r\n", 30, "List-Id: offers\r\n")),
        (14, set(), message("offers@qantas.com.au", "you@example.com", "30% off", "Sale\r\n", 35, "List-Id: offers\r\n")),
    ]
    sent = [
        (1, {"\\Seen"}, message("you@example.com", "priya@northwind.vc", "Re: Earlier", "Sure\r\n", 39)),
        (2, {"\\Seen"}, message("you@example.com", "Priya <priya@northwind.vc>, tom@acme.co", "Re: Earlier 2", "Yes\r\n", 49)),
    ]
    return {"INBOX": inbox, "Archive": archive, "Sent Messages": sent, "Trash": []}


MAILBOXES = build()
LOCK = threading.Lock()


def parse_set(text, uids):
    chosen = set()
    for part in text.split(","):
        if ":" in part:
            a, b = part.split(":")
            low = int(a)
            high = max(uids) if b == "*" else int(b)
            chosen.update(u for u in uids if low <= u <= high)
        else:
            chosen.add(int(part))
    return [u for u in sorted(uids) if u in chosen]


class IMAPHandler(socketserver.StreamRequestHandler):
    def send(self, text):
        self.wfile.write(text.encode() if isinstance(text, str) else text)

    def handle(self):
        selected = None
        self.send("* OK [CAPABILITY IMAP4rev1 LITERAL+] Fake IMAP ready\r\n")
        while True:
            raw = self.rfile.readline()
            if not raw:
                return
            line = raw.decode(errors="replace").rstrip("\r\n")
            LOG.write(line if "LOGIN" not in line.upper() else line.split(" LOGIN ")[0] + " LOGIN ***")
            LOG.write("\n")
            tag, _, rest = line.partition(" ")
            command, _, args = rest.partition(" ")
            command = command.upper()
            if command == "UID":
                command, _, args = args.partition(" ")
                command = "UID " + command.upper()
            with LOCK:
                if command == "LOGIN":
                    tokens = [quoted or bare for quoted, bare in re.findall(r'"((?:[^"\\]|\\.)*)"|(\S+)', args)]
                    user, password = (tokens + ["", ""])[:2]
                    if user == USER and password == PASSWORD:
                        self.send(f"{tag} OK Logged in\r\n")
                    else:
                        self.send(f"{tag} NO [AUTHENTICATIONFAILED] Invalid credentials\r\n")
                elif command == "AUTHENTICATE":
                    self.send("+ \r\n")
                    answer = base64.b64decode(self.rfile.readline().strip() or b"").decode(errors="replace")
                    parts = dict(p.split("=", 1) for p in answer.split("\x01") if "=" in p)
                    if parts.get("user") == USER and parts.get("auth") == "Bearer good-token":
                        self.send(f"{tag} OK AUTHENTICATE completed\r\n")
                    else:
                        self.send("+ eyJzdGF0dXMiOiI0MDEifQ==\r\n")
                        self.rfile.readline()
                        self.send(f"{tag} NO AUTHENTICATE failed\r\n")
                elif command == "CAPABILITY":
                    self.send("* CAPABILITY IMAP4rev1 MOVE UIDPLUS LITERAL+\r\n" + f"{tag} OK CAPABILITY done\r\n")
                elif command == "LIST":
                    self.send('* LIST (\\HasNoChildren) "/" INBOX\r\n'
                              '* LIST (\\HasNoChildren \\Archive) "/" "Archive"\r\n'
                              '* LIST (\\HasNoChildren \\Sent) "/" "Sent Messages"\r\n'
                              '* LIST (\\HasNoChildren \\Trash) "/" {5}\r\nTrash\r\n'
                              f"{tag} OK LIST done\r\n")
                elif command in ("SELECT", "EXAMINE"):
                    name = args.strip().strip('"')
                    if name not in MAILBOXES:
                        self.send(f"{tag} NO No such mailbox\r\n")
                        continue
                    selected = name
                    box = MAILBOXES[name]
                    next_uid = max([u for u, _, _ in box], default=0) + 1
                    self.send(f"* {len(box)} EXISTS\r\n* OK [UIDVALIDITY 42] UIDs valid\r\n* OK [UIDNEXT {next_uid}] next\r\n"
                              f"{tag} OK [READ-WRITE] {command} done\r\n")
                elif command == "UID SEARCH":
                    uids = " ".join(str(u) for u, _, _ in MAILBOXES[selected])
                    self.send(f"* SEARCH {uids}\r\n{tag} OK SEARCH done\r\n".replace("SEARCH \r\n", "SEARCH\r\n"))
                elif command == "UID FETCH":
                    sequence, _, items = args.partition(" ")
                    box = MAILBOXES[selected]
                    for uid in parse_set(sequence, [u for u, _, _ in box]):
                        index, (_, flags, raw_message) = next((i, m) for i, m in enumerate(box) if m[0] == uid)
                        parts = [f"UID {uid}"]
                        if "FLAGS" in items:
                            parts.append("FLAGS (" + " ".join(sorted(flags)) + ")")
                        if "INTERNALDATE" in items:
                            parts.append('INTERNALDATE "17-Jul-2026 02:44:25 +0000"')
                        body = raw_message.encode()
                        chunks = []
                        if "HEADER.FIELDS" in items:
                            header = body.split(b"\r\n\r\n")[0] + b"\r\n\r\n"
                            fields = re.search(r"HEADER\.FIELDS \(([^)]*)\)", items).group(1)
                            chunks.append((f"BODY[HEADER.FIELDS ({fields})]", header))
                        if "BODY.PEEK[]" in items or "BODY[]" in items:
                            chunks.append(("BODY[]<0>", body))
                        out = f"* {index + 1} FETCH (" + " ".join(parts)
                        self.send(out.encode())
                        for name, data in chunks:
                            self.send(f" {name} {{{len(data)}}}\r\n".encode() + data)
                        self.send(")\r\n")
                    self.send(f"{tag} OK FETCH done\r\n")
                elif command == "UID STORE":
                    sequence, mode, flag_text = args.split(" ", 2)
                    flags = set(flag_text.strip("()").split())
                    box = MAILBOXES[selected]
                    for uid in parse_set(sequence, [u for u, _, _ in box]):
                        for entry in box:
                            if entry[0] == uid:
                                if mode.startswith("+"):
                                    entry[1].update(flags)
                                else:
                                    entry[1].difference_update(flags)
                    self.send(f"{tag} OK STORE done\r\n")
                elif command == "UID MOVE":
                    sequence, _, target = args.partition(" ")
                    target = target.strip('"')
                    box = MAILBOXES[selected]
                    moving = parse_set(sequence, [u for u, _, _ in box])
                    for uid in moving:
                        entry = next(m for m in box if m[0] == uid)
                        box.remove(entry)
                        MAILBOXES[target].append((1000 + uid, entry[1], entry[2]))
                    self.send(f"{tag} OK MOVE done\r\n")
                elif command == "APPEND":
                    match = re.search(r'"([^"]+)" \(([^)]*)\) \{(\d+)(\+?)\}', args)
                    name, flags, size, plus = match.group(1), match.group(2), int(match.group(3)), match.group(4)
                    if not plus:
                        self.send("+ Ready\r\n")
                    data = self.rfile.read(size)
                    self.rfile.readline()
                    MAILBOXES[name].append((500 + len(MAILBOXES[name]), set(flags.split()), data.decode(errors="replace")))
                    self.send(f"{tag} OK APPEND done\r\n")
                elif command == "LOGOUT":
                    self.send(f"* BYE\r\n{tag} OK LOGOUT done\r\n")
                    return
                else:
                    self.send(f"{tag} BAD Unknown command {command}\r\n")


class SMTPHandler(socketserver.StreamRequestHandler):
    def send(self, text):
        self.wfile.write(text.encode())

    def handle(self):
        self.send("220 fake.smtp ready\r\n")
        while True:
            raw = self.rfile.readline()
            if not raw:
                return
            line = raw.decode(errors="replace").rstrip("\r\n")
            verb = line.split(" ")[0].upper()
            if verb == "EHLO":
                self.send("250-fake.smtp\r\n250-AUTH PLAIN LOGIN\r\n250 8BITMIME\r\n")
            elif verb == "AUTH":
                token = line.split(" ")[2]
                _, user, password = base64.b64decode(token).decode().split("\0")
                self.send("235 OK\r\n" if (user, password) == (USER, PASSWORD) else "535 Bad credentials\r\n")
            elif verb in ("MAIL", "RCPT"):
                self.send("250 OK\r\n")
            elif verb == "DATA":
                self.send("354 Go ahead\r\n")
                lines = []
                while True:
                    data_line = self.rfile.readline()
                    if data_line in (b".\r\n", b""):
                        break
                    lines.append(data_line[1:] if data_line.startswith(b"..") else data_line)
                with open("smtp-received.eml", "wb") as handle:
                    handle.write(b"".join(lines))
                self.send("250 Queued\r\n")
            elif verb == "QUIT":
                self.send("221 Bye\r\n")
                return
            else:
                self.send("500 Unknown\r\n")


class MicrosoftHandler(http.server.BaseHTTPRequestHandler):
    """Stands in for login.microsoftonline.com and graph.microsoft.com."""

    def reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        if self.path.endswith("/oauth2/v2.0/token"):
            form = {k: v[0] for k, v in urllib.parse.parse_qs(body.decode()).items()}
            claims = base64.urlsafe_b64encode(json.dumps({"email": USER, "name": "You Test"}).encode()).decode().rstrip("=")
            ok = {"access_token": "good-token", "refresh_token": "refresh-2", "expires_in": 3599, "token_type": "Bearer",
                  "id_token": f"eyJhbGciOiJub25lIn0.{claims}."}
            if form.get("client_id") != "11111111-2222-3333-4444-555555555555":
                self.reply(400, {"error": "unauthorized_client", "error_description": "AADSTS700016: Application not found."})
            elif form.get("grant_type") == "authorization_code" and form.get("code") == "code-1" and len(form.get("code_verifier", "")) >= 43:
                self.reply(200, ok)
            elif form.get("grant_type") == "refresh_token" and form.get("refresh_token") == "refresh-1":
                self.reply(200, ok)
            else:
                self.reply(400, {"error": "invalid_grant", "error_description": "AADSTS70000: The provided grant is invalid.\r\nTrace ID: x"})
        elif self.path == "/v1.0/me/sendMail":
            if self.headers.get("Authorization") != "Bearer good-token":
                self.reply(401, {"error": {"code": "InvalidAuthenticationToken", "message": "Access token is empty."}})
                return
            with open("graph-sent.eml", "wb") as handle:
                handle.write(base64.b64decode(body))
            self.send_response(202)
            self.send_header("Content-Length", "0")
            self.end_headers()
        else:
            self.reply(404, {"error": "not found"})


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    imap = Server(("127.0.0.1", 1143), IMAPHandler)
    smtp = Server(("127.0.0.1", 1025), SMTPHandler)
    threading.Thread(target=smtp.serve_forever, daemon=True).start()
    web = http.server.ThreadingHTTPServer(("127.0.0.1", 1080), MicrosoftHandler)
    threading.Thread(target=web.serve_forever, daemon=True).start()
    print("fake mail server on 1143 (IMAP) and 1025 (SMTP)", flush=True)
    try:
        imap.serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)
