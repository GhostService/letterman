// Shared helpers for main.pb.js. PocketBase runs each hook handler in an isolated
// context, so handlers load this file with require() instead of sharing top-level code.

// Personal data fields that are encrypted at rest, per collection.
const ENCRYPTED = {
  users: ["name", "phone", "school", "grade"],
  signups: ["name", "email", "phone", "school", "grade"],
  hour_logs: ["place_name", "address", "comments", "signer_name", "signature"],
  calendar_events: ["title", "location", "notes"],
}
const PREFIX = "enc:"

// AES-256-GCM key from the environment. Exactly 32 characters (see FIRST_SETUP.md).
function key() {
  const k = $os.getenv("PB_FIELD_KEY")
  if (k.length !== 32) {
    throw new Error("PB_FIELD_KEY must be set to exactly 32 characters. See FIRST_SETUP.md.")
  }
  return k
}

function encryptRecord(record) {
  const fields = ENCRYPTED[record.collection().name]
  if (!fields) return
  const k = key()
  for (const f of fields) {
    const v = record.getString(f)
    // Values loaded from the DB are already encrypted; never double-encrypt.
    if (v !== "" && !v.startsWith(PREFIX)) {
      record.set(f, PREFIX + $security.encrypt(v, k))
    }
  }
}

function decryptRecord(record) {
  const fields = ENCRYPTED[record.collection().name]
  if (!fields) return
  const k = key()
  for (const f of fields) {
    const v = record.getString(f)
    if (!v.startsWith(PREFIX)) continue
    try {
      record.set(f, toString($security.decrypt(v.slice(PREFIX.length), k)))
    } catch (_) {
      // Not our ciphertext (e.g. someone typed "enc:" themselves); show it as-is.
    }
  }
}

function signupCount(app, opportunityId) {
  const row = new DynamicModel({ n: 0 })
  app.db()
    .newQuery("SELECT COUNT(*) AS n FROM signups WHERE opportunity = {:id}")
    .bind({ id: opportunityId })
    .one(row)
  return row.n
}

// Server-side rules for the supervisor signature on an hour log.
function stampSignature(record) {
  // Confirmed by an organization (set only by confirmAttendance): its stamp stands without a drawn signature.
  if (record.getString("confirmed_by") !== "") return
  // Already signed before this save: keep the original stamp (clients can't edit signed logs anyway).
  if (record.original().getString("signature") !== "") return

  const sig = record.getString("signature")
  if (sig === "") {
    record.set("signer_name", "")
    record.set("signed_at", "")
    return
  }
  if (record.getString("signer_name").trim() === "") {
    throw new BadRequestError("The supervisor's name is required with a signature.")
  }
  // Base64 of the PNG file header.
  if (!sig.startsWith("iVBORw0KGgo")) {
    throw new BadRequestError("The signature must be a PNG image.")
  }
  // The server decides when it was signed so it can't be backdated.
  record.set("signed_at", new DateTime())
}

// The listing hasn't finished yet, so its attendees still care about changes.
function isUpcoming(opportunity) {
  const ends = opportunity.getDateTime("starts_at").unix() + opportunity.getFloat("duration_hours") * 3600
  return ends > new DateTime().unix()
}

// Account emails of everyone signed up (the account email isn't one of the encrypted fields).
function attendeeEmails(app, opportunityId) {
  return app.findRecordsByFilter("signups", "opportunity = {:id}", "", 0, 0, { id: opportunityId })
    .map((s) => {
      try {
        return app.findRecordById("users", s.getString("volunteer")).email()
      } catch (_) {
        return ""
      }
    })
    .filter((email) => email !== "")
}

// One email with every attendee in BCC, so they can't see each other's addresses.
// Best effort: a mail problem is logged but never fails the organization's save or delete.
function notifyAttendees(app, emails, subject, text) {
  if (emails.length === 0) return
  const meta = app.settings().meta
  try {
    app.newMailClient().send(new MailerMessage({
      from: { address: meta.senderAddress, name: meta.senderName },
      to: [{ address: meta.senderAddress, name: meta.senderName }],
      bcc: emails.map((address) => ({ address })),
      subject,
      text,
    }))
  } catch (err) {
    app.logger().warn("Couldn't email attendees", "subject", subject, "count", emails.length, "error", String(err))
  }
}

// The organization confirmed this volunteer came: their hours for the shift count as signed.
// Signs the student's own unsigned log for the shift (corrected to the listing's time and length),
// creates one if they didn't log it, and leaves an already signed log alone.
function confirmAttendance(app, opportunity, volunteerId, operatorId) {
  const operator = app.findRecordById("users", operatorId)
  decryptRecord(operator) // in memory only, for the name; never saved
  const signer = [operator.getString("name"), opportunity.getString("org_name")].filter((s) => s !== "").join(", ")

  const existing = app.findRecordsByFilter("hour_logs", "owner = {:owner} && opportunity = {:opportunity}", "-created", 1, 0,
    { owner: volunteerId, opportunity: opportunity.id })
  let log = existing.length > 0 ? existing[0] : null
  if (log && (log.getString("signature") !== "" || log.getString("confirmed_by") !== "")) return

  if (!log) {
    log = new Record(app.findCollectionByNameOrId("hour_logs"))
    log.set("owner", volunteerId)
    log.set("opportunity", opportunity.id)
    log.set("place_name", opportunity.getString("org_name"))
    log.set("address", opportunity.getString("address"))
    log.set("comments", opportunity.getString("title"))
  }
  log.set("started_at", opportunity.getDateTime("starts_at"))
  log.set("hours", opportunity.getFloat("duration_hours"))
  log.set("confirmed_by", operatorId)
  log.set("signer_name", signer)
  log.set("signed_at", new DateTime())
  app.save(log)
}

module.exports = { key, encryptRecord, decryptRecord, signupCount, stampSignature, isUpcoming, attendeeEmails, notifyAttendees, confirmAttendance }
