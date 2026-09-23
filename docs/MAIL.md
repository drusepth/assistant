# MAIL.md

Whether this server sends email of its own. **It doesn't have to, and by
default it doesn't** (D-instance-mail). Everything works without it:

- **Invitations** are links an admin copies and sends however the household
  already talks (D15).
- **Password resets** are links too. A household admin makes one from the
  Household page (**Reset link** beside a member). The person running the
  server can always make one from the shell, which is the way back in when the
  only admin is the one locked out:

  ```sh
  bin/rails password:reset_link EMAIL=you@example.com
  # under Kamal:
  bin/kamal app exec -i "bin/rails password:reset_link EMAIL=you@example.com"
  ```

  A handed-over link works once and expires in 24 hours. Saved passwords and
  the diary still need the member's recovery code, whoever resets.
- **Notifications** go by webhook, browser push, text, or Signal. Email
  notifications can send through a member's own linked mailbox
  (Settings → Connected accounts, with sending on), from them to them.

## Why not just send mail directly?

Sending without a relay doesn't put mail in spam. It stops it arriving at all.
Home internet providers block outbound port 25, home IP ranges are on the
blocklists every large mail provider checks, and Gmail and Yahoo reject mail
without SPF, DKIM, and matching reverse DNS. A relay you already have an
account with solves all three.

## Turning it on

Point the app at any SMTP server you can log in to and restart. What it adds:
the "email me a reset link" form on the sign-in page, and a "This server's
email" choice for notification email.

| ENV | Meaning |
|---|---|
| `SMTP_ADDRESS` | The SMTP server. Setting this is what turns instance mail on |
| `SMTP_PORT` | `587` (default, STARTTLS) or `465` (TLS from the start); `25` for a LAN relay |
| `SMTP_USERNAME` / `SMTP_PASSWORD` | Login. Leave both unset for a relay that takes unauthenticated mail |
| `SMTP_FROM` | The sender, e.g. `Home Assistant <home@example.org>`. Defaults to the username when it is an address |
| `SMTP_AUTHENTICATION` | `plain` (default), `login`, or `cram_md5` |
| `SMTP_DOMAIN` | HELO domain, only if your provider asks for one |
| `APP_HOST` | This server's public address, e.g. `https://assistant.example.org`. Required for emailed reset links, which are never built from a visitor's own request |

Examples:

```sh
# Gmail, or any Google Workspace mailbox (needs an app password)
SMTP_ADDRESS=smtp.gmail.com
SMTP_USERNAME=you@gmail.com
SMTP_PASSWORD=your-app-password

# Fastmail
SMTP_ADDRESS=smtp.fastmail.com
SMTP_PORT=465
SMTP_USERNAME=you@fastmail.com
SMTP_PASSWORD=your-app-password

# A transactional service (Postmark, Resend, Mailgun, SES, Brevo…):
# use the SMTP host, username, and key they give you, and a sender
# address on a domain you've verified with them.
SMTP_ADDRESS=smtp.example-provider.com
SMTP_USERNAME=apikey
SMTP_PASSWORD=...
SMTP_FROM=home@yourdomain.org
```

Under Kamal, put the password in `.kamal/secrets` and list the rest under
`env:` in `config/deploy.yml` (the commented lines there show where). The
admin overview's **Email** card shows whether mail is on and who it sends as.
