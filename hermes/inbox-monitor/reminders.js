// Apple Reminders helper for the inbox monitor (JXA). Only called by ./im.
//   lists
//   ensure-list <list>
//   open <list>                 open reminders: title, due, priority, flagged
//   get <id>                    one reminder (any state); {"missing":true} only for "Can't get object" (-1728)
//   create <list> <title> <notes> <due|-> <high|medium|low|none> <flag|noflag> <marker> <managed lists, comma-separated>
//                               idempotent: if a reminder in any managed list already has <marker> in its notes,
//                               returns that one with "existing": true instead of creating another
//   complete <id>
//   update <id> priority|flag|due <value>
// Due: YYYY-MM-DD (all-day) or YYYY-MM-DDTHH:MM (local wall time; run.sh sets TZ=Asia/Bangkok).
// Output: one JSON value on stdout.

const PRI = { high: 1, medium: 5, low: 9, none: 0 };
const PRI_NAME = (n) => (n === 0 ? "none" : n <= 4 ? "high" : n <= 5 ? "medium" : "low");

function parseDue(s) {
  let m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (m) return { allday: true, date: new Date(+m[1], +m[2] - 1, +m[3]) };
  m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(s);
  if (m) return { allday: false, date: new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]) };
  throw new Error("bad due date (want YYYY-MM-DD or YYYY-MM-DDTHH:MM): " + s);
}

function iso(d) {
  if (!d) return null;
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

function info(r) {
  return {
    id: r.id(),
    title: r.name(),
    completed: r.completed(),
    priority: PRI_NAME(r.priority()),
    flagged: r.flagged(),
    due: iso(r.dueDate()),
    remind_at: iso(r.remindMeDate()),
    notes: r.body() || "",
  };
}

function dueProps(s) {
  if (s === "-") return {};
  const d = parseDue(s);
  return d.allday ? { alldayDueDate: d.date } : { dueDate: d.date };
}

function priority(s) {
  if (!(s in PRI)) throw new Error("priority must be high|medium|low|none: " + s);
  return PRI[s];
}

function flag(s) {
  if (s !== "flag" && s !== "noflag") throw new Error("flag must be flag|noflag: " + s);
  return s === "flag";
}

function findList(app, name) {
  const ls = app.lists.whose({ name: name })();
  if (ls.length === 0) throw new Error("no such list: " + name);
  return ls[0];
}

function byId(app, id) {
  const r = app.reminders.byId(id);
  try { r.name(); } catch (e) {
    if (e.errorNumber === -1728) return null;  // "Can't get object": deleted
    throw e;                                   // timeouts etc. must not look like a deletion
  }
  return r;
}

function run(argv) {
  const app = Application("Reminders");
  const [cmd, ...a] = argv;
  try {
    switch (cmd) {
      case "lists":
        return JSON.stringify(app.lists.name());
      case "ensure-list": {
        if (app.lists.whose({ name: a[0] })().length === 0) {
          app.lists.push(app.List({ name: a[0] }));
          return JSON.stringify({ created: a[0] });
        }
        return JSON.stringify({ exists: a[0] });
      }
      case "open": {
        // Bulk property reads: whose() on reminders is slow enough to time out.
        const rs = findList(app, a[0]).reminders;
        const done = rs.completed(), names = rs.name(), due = rs.dueDate(), pri = rs.priority(), fl = rs.flagged();
        const res = [];
        for (let i = 0; i < names.length; i++)
          if (!done[i]) res.push({ title: names[i], due: iso(due[i]), priority: PRI_NAME(pri[i]), flagged: fl[i] });
        return JSON.stringify(res);
      }
      case "get": {
        const r = byId(app, a[0]);
        return JSON.stringify(r ? info(r) : { id: a[0], missing: true });
      }
      case "create": {
        if (a.length !== 8) throw new Error("create needs 8 args: list title notes due priority flag marker lists");
        const [list, title, notes, due, pri, fl, marker, managed] = a;
        const l = findList(app, list);
        for (const name of managed.split(",")) {  // a retry may pick another list: look in all of them
          const ls = app.lists.whose({ name: name })();
          if (ls.length === 0) continue;
          const i = ls[0].reminders.body().findIndex((b) => b && b.includes(marker));
          if (i >= 0) return JSON.stringify(Object.assign(info(ls[0].reminders[i]), { existing: true }));
        }
        const r = app.Reminder(Object.assign(
          { name: title, body: notes, priority: priority(pri), flagged: flag(fl) }, dueProps(due)));
        l.reminders.push(r);
        return JSON.stringify(info(r));
      }
      case "complete": {
        const r = byId(app, a[0]);
        if (!r) throw new Error("no such reminder: " + a[0]);
        r.completed = true;
        return JSON.stringify(info(r));
      }
      case "update": {
        const r = byId(app, a[0]);
        if (!r) throw new Error("no such reminder: " + a[0]);
        if (a[1] === "priority") r.priority = priority(a[2]);
        else if (a[1] === "flag") r.flagged = flag(a[2]);
        else if (a[1] === "due") {
          const d = parseDue(a[2]);
          if (d.allday) r.alldayDueDate = d.date; else r.dueDate = d.date;
        } else throw new Error("update field must be priority|flag|due");
        return JSON.stringify(info(r));
      }
      default:
        throw new Error("unknown command: " + cmd);
    }
  } catch (e) {
    return JSON.stringify({ error: String(e.message || e) });
  }
}
