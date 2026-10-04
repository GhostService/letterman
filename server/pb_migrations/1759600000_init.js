/// <reference path="../pb_data/types.d.ts" />

// Creates every collection, field and API rule the app needs.
// Rules are the security boundary: the iOS app is untrusted, so every check that matters lives here.
// Text fields that hold personal data are encrypted by pb_hooks (see lib.js), so their `max`
// leaves room for the ciphertext, which is about 1.4x the plain text plus a few bytes.

migrate((app) => {
  const VERIFIED = "@request.auth.verified = true"

  // ---- settings ----
  const settings = app.settings()
  settings.meta.appName = "Letterman"
  settings.rateLimits.enabled = true
  // PocketBase sits behind Caddy, which sets X-Forwarded-For to the real client IP.
  settings.trustedProxy.headers = ["X-Forwarded-For"]
  settings.trustedProxy.useLeftmostIP = false
  // Nightly backup zip in pb_data/backups at 3:00 AM server time, keeping the last 7.
  settings.backups.cron = "0 3 * * *"
  settings.backups.cronMaxKeep = 7
  app.save(settings)

  // ---- users (built-in auth collection) ----
  const users = app.findCollectionByNameOrId("users")
  users.fields.removeByName("avatar")
  const name = users.fields.getByName("name")
  name.required = true
  name.max = 1000
  users.fields.add(new TextField({ name: "phone", max: 500 }))
  users.fields.add(new TextField({ name: "school", max: 1000 }))
  users.fields.add(new TextField({ name: "grade", max: 200 }))
  users.fields.add(new SelectField({ name: "role", values: ["volunteer", "operator"], maxSelect: 1 }))
  users.fields.add(new BoolField({ name: "operator_requested" }))
  users.fields.add(new TextField({ name: "org_name", max: 200 }))
  users.fields.add(new NumberField({ name: "hours_goal", min: 0, max: 10000 }))
  // Only an admin (superuser in the dashboard) can make someone an operator.
  users.listRule = "id = @request.auth.id"
  users.viewRule = "id = @request.auth.id"
  users.createRule = "@request.body.role:isset = false"
  users.updateRule = "id = @request.auth.id && @request.body.role:isset = false"
  users.deleteRule = "id = @request.auth.id"
  app.save(users)

  // ---- hour_logs ----
  const hourLogs = new Collection({
    type: "base",
    name: "hour_logs",
    listRule: `${VERIFIED} && owner = @request.auth.id`,
    viewRule: `${VERIFIED} && owner = @request.auth.id`,
    createRule: `${VERIFIED} && @request.body.owner = @request.auth.id`,
    // Signed entries are locked: updates only while there is no signature yet.
    updateRule: `${VERIFIED} && owner = @request.auth.id && signature = "" && (@request.body.owner:isset = false || @request.body.owner = @request.auth.id)`,
    deleteRule: `${VERIFIED} && owner = @request.auth.id`,
    fields: [
      { name: "owner", type: "relation", required: true, collectionId: users.id, cascadeDelete: true, maxSelect: 1 },
      { name: "started_at", type: "date", required: true },
      { name: "hours", type: "number", required: true, min: 0.25, max: 24 },
      { name: "place_name", type: "text", required: true, max: 1000 },
      { name: "address", type: "text", max: 2000 },
      { name: "comments", type: "text", max: 8000 },
      // Base64 PNG of the supervisor's signature (encrypted like everything else).
      { name: "signature", type: "text", max: 2000000 },
      { name: "signer_name", type: "text", max: 1000 },
      { name: "signed_at", type: "date" },
      { name: "created", type: "autodate", onCreate: true },
      { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
    ],
    indexes: ["CREATE INDEX idx_hour_logs_owner ON hour_logs (owner, started_at)"],
  })
  app.save(hourLogs)

  // ---- opportunities ----
  const opportunities = new Collection({
    type: "base",
    name: "opportunities",
    listRule: VERIFIED,
    viewRule: VERIFIED,
    createRule: `${VERIFIED} && @request.auth.role = "operator" && @request.body.operator = @request.auth.id`,
    updateRule: `${VERIFIED} && @request.auth.role = "operator" && operator = @request.auth.id && (@request.body.operator:isset = false || @request.body.operator = @request.auth.id)`,
    deleteRule: `${VERIFIED} && operator = @request.auth.id`,
    fields: [
      { name: "operator", type: "relation", required: true, collectionId: users.id, cascadeDelete: true, maxSelect: 1 },
      { name: "title", type: "text", required: true, max: 200 },
      { name: "org_name", type: "text", required: true, max: 200 },
      { name: "description", type: "text", max: 5000 },
      { name: "address", type: "text", required: true, max: 500 },
      { name: "starts_at", type: "date", required: true },
      { name: "duration_hours", type: "number", required: true, min: 0.25, max: 24 },
      { name: "spots_needed", type: "number", required: true, min: 1, max: 1000, onlyInt: true },
      { name: "created", type: "autodate", onCreate: true },
      { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
    ],
    indexes: ["CREATE INDEX idx_opportunities_starts ON opportunities (starts_at)"],
  })
  app.save(opportunities)

  // ---- signups ----
  // name/email/phone/school/grade are a snapshot of the volunteer's contact info, copied by a hook,
  // so operators never need read access to the users collection.
  const signups = new Collection({
    type: "base",
    name: "signups",
    listRule: `${VERIFIED} && (volunteer = @request.auth.id || opportunity.operator = @request.auth.id)`,
    viewRule: `${VERIFIED} && (volunteer = @request.auth.id || opportunity.operator = @request.auth.id)`,
    createRule: `${VERIFIED} && @request.auth.role != "operator" && @request.body.volunteer = @request.auth.id`,
    updateRule: null,
    deleteRule: `${VERIFIED} && volunteer = @request.auth.id`,
    fields: [
      { name: "opportunity", type: "relation", required: true, collectionId: opportunities.id, cascadeDelete: true, maxSelect: 1 },
      { name: "volunteer", type: "relation", required: true, collectionId: users.id, cascadeDelete: true, maxSelect: 1 },
      { name: "name", type: "text", max: 1000 },
      { name: "email", type: "text", max: 1000 },
      { name: "phone", type: "text", max: 500 },
      { name: "school", type: "text", max: 1000 },
      { name: "grade", type: "text", max: 200 },
      { name: "created", type: "autodate", onCreate: true },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_signups_unique ON signups (opportunity, volunteer)"],
  })
  app.save(signups)

  // ---- calendar_events (a volunteer's own custom entries) ----
  const calendarEvents = new Collection({
    type: "base",
    name: "calendar_events",
    listRule: `${VERIFIED} && owner = @request.auth.id`,
    viewRule: `${VERIFIED} && owner = @request.auth.id`,
    createRule: `${VERIFIED} && @request.body.owner = @request.auth.id`,
    updateRule: `${VERIFIED} && owner = @request.auth.id && (@request.body.owner:isset = false || @request.body.owner = @request.auth.id)`,
    deleteRule: `${VERIFIED} && owner = @request.auth.id`,
    fields: [
      { name: "owner", type: "relation", required: true, collectionId: users.id, cascadeDelete: true, maxSelect: 1 },
      { name: "title", type: "text", required: true, max: 1000 },
      { name: "starts_at", type: "date", required: true },
      { name: "duration_hours", type: "number", min: 0, max: 24 },
      { name: "location", type: "text", max: 2000 },
      { name: "notes", type: "text", max: 8000 },
      { name: "created", type: "autodate", onCreate: true },
      { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
    ],
    indexes: ["CREATE INDEX idx_calendar_events_owner ON calendar_events (owner, starts_at)"],
  })
  app.save(calendarEvents)
}, (app) => {
  for (const n of ["calendar_events", "signups", "opportunities", "hour_logs"]) {
    app.delete(app.findCollectionByNameOrId(n))
  }
})
