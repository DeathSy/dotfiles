---
name: google-workspace
description: Interact with the user's Google Workspace (Gmail, Drive, Docs, Sheets, Slides, Calendar, Tasks, People, Chat, Forms, Keep, Meet) through the `gws` CLI. Use whenever the user wants to read/send email, upload or manage Drive files and folders, read/write Google Sheets or Docs, create/list calendar events, manage tasks, or otherwise touch their Google Workspace. Triggers: "gws", "google drive", "upload to drive", "google sheet", "gmail", "google calendar", "google doc", "my google workspace".
---

# Google Workspace via `gws`

`gws` is a Google Workspace CLI already installed and authenticated for this user (OAuth2, refresh token stored). It exposes the full REST surface of each Google API plus a few ergonomic helpers. Prefer it over the in-session Anthropic Google connectors, which are read-only.

## Auth

Auth is usually already configured — check first:

```bash
gws auth status
```

If it reports missing/expired credentials or too few scopes, the user must run the login themselves (it opens a browser). Ask them to run, in their terminal with the `!` prefix:

```
gws auth login --services gmail,tasks,calendar,sheets,drive
```

Add other services to `--services` as needed (e.g. `docs,slides`). Never run `auth login` yourself in a way that blocks — it needs interactive browser consent. Never run `gws auth export` (prints decrypted credentials) unless the user explicitly asks.

## Command model

```
gws <service> <resource> [sub-resource] <method> [flags]
```

- `--params '<JSON>'` — URL/query parameters (GET/list).
- `--json '<JSON>'` — request body (POST/PATCH/PUT).
- `--upload <PATH>` — attach local file as media (uploads).
- `--format json|table|yaml|csv` — output format (default json). Use `table` for human-readable listings.
- `--page-all` `--page-limit N` — auto-paginate (NDJSON, one page per line).
- `--dry-run` — validate locally without sending. Use this first for any write you're unsure about.

**Discover any method's exact parameters** before calling it:

```bash
gws schema drive.files.list
gws schema sheets.spreadsheets.values.update --resolve-refs
gws schema gmail.users.messages.send
```

Services: `drive sheets docs slides gmail calendar tasks people chat classroom forms keep meet admin-reports`.

## Ergonomic helpers (prefix `+`)

- `gws drive +upload <file> --parent <FOLDER_ID> [--name '<Name>']` — upload with auto MIME detection.
- `gws gmail +send`, `gws gmail +triage` (unread summary), `gws gmail +watch` (stream new mail as NDJSON).

Run `gws <service> --help` to list a service's resources, and `gws <service> +<helper> --help` for helper flags.

## Common recipes

### Drive — list a folder
```bash
gws drive files list --params '{"q":"'\''FOLDER_ID'\'' in parents and trashed=false","fields":"files(id,name,mimeType,modifiedTime,size)"}' --format table
```

### Drive — upload a local file into a folder
```bash
gws drive +upload "/path/to/file.docx" --parent FOLDER_ID --name "File Name.docx"
```

### Drive — upload a .docx AND convert it to a native Google Doc
Set the target `mimeType` to the Google-native type; Drive converts the uploaded media on the way in:
```bash
gws drive files create \
  --json '{"name":"My Report","parents":["FOLDER_ID"],"mimeType":"application/vnd.google-apps.document"}' \
  --upload "/path/to/report.docx"
```
(Sheets → `application/vnd.google-apps.spreadsheet`; Slides → `...presentation`.)

### Drive — update an existing file's contents in place (avoid duplicates)
Find the file id via a list, then:
```bash
gws drive files update --params '{"fileId":"FILE_ID"}' --upload "/path/to/report.docx"
```
Before uploading a "monthly"/named artifact, **list the folder and check for an existing same-name file** — update it in place rather than creating a duplicate.

### Sheets — read a range
```bash
gws sheets spreadsheets values get --params '{"spreadsheetId":"SHEET_ID","range":"Sheet1!A1:D20"}' --format csv
```

### Sheets — write a range
```bash
gws sheets spreadsheets values update \
  --params '{"spreadsheetId":"SHEET_ID","range":"Sheet1!A1","valueInputOption":"USER_ENTERED"}' \
  --json '{"values":[["Name","Score"],["Alice","91"]]}'
```

### Gmail — triage / read / send
```bash
gws gmail +triage
gws gmail users messages list --params '{"userId":"me","q":"is:unread newer_than:7d","maxResults":20}'
gws gmail +send   # then follow its prompts/flags (see --help) for to/subject/body
```

### Calendar — list & create
```bash
gws calendar events list --params '{"calendarId":"primary","timeMin":"2026-08-11T00:00:00Z","singleEvents":true,"orderBy":"startTime","maxResults":20}' --format table
gws calendar events insert --params '{"calendarId":"primary"}' --json '{"summary":"Sync","start":{"dateTime":"2026-08-12T10:00:00+07:00"},"end":{"dateTime":"2026-08-12T10:30:00+07:00"}}'
```

### Tasks
```bash
gws tasks tasklists list --format table
gws tasks tasks list --params '{"tasklist":"TASKLIST_ID"}' --format table
gws tasks tasks insert --params '{"tasklist":"TASKLIST_ID"}' --json '{"title":"Follow up","notes":"..."}'
```

## Safety & etiquette

- These are the user's real account and real data. Treat every write (send email, create/modify/delete files or events, share/permissions) as a **side-effecting action**: state exactly what you're about to do and confirm before doing it, unless the user has already told you to proceed for this specific task. Reversible reads (list/get) need no confirmation.
- Prefer `--dry-run` first for unfamiliar writes; prefer updating an existing file over creating duplicates; prefer least-privilege queries (`trashed=false`, narrow `fields`, `q` filters).
- Never send data to recipients, folders, or endpoints the user didn't specify. Never print or export credentials. Never delete/trash without explicit confirmation.
- Shared drives: add `"supportsAllDrives":true` (and `"includeItemsFromAllDrives":true` for lists) to `--params` when operating on shared-drive items.

## Related

The recurring SAST report goes to a specific Drive folder with a monthly naming convention — see the project memory note `sast-report-drive-destination` for the exact folder id, naming, and upload command.
