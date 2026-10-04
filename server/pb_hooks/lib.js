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

// AES-256-GCM key from the environment. Exactly 32 characters (see docs/SERVER_SETUP.md).
function key() {
  const k = $os.getenv("PB_FIELD_KEY")
  if (k.length !== 32) {
    throw new Error("PB_FIELD_KEY must be set to exactly 32 characters. See docs/SERVER_SETUP.md.")
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

module.exports = { key, encryptRecord, decryptRecord, signupCount, stampSignature }
