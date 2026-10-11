/// <reference path="../pb_data/types.d.ts" />

// Organizations confirm who came to a shift. Confirming signs that student's hours for the shift
// (see the signups hook in main.pb.js), so a confirmed log counts just like one with a drawn signature.

const LOG_CREATE_LOCK = ` && @request.body.confirmed_by:isset = false`
const LOG_UPDATE_LOCK = ` && confirmed_by = "" && @request.body.confirmed_by:isset = false`

migrate((app) => {
  const signups = app.findCollectionByNameOrId("signups")
  signups.fields.add(new BoolField({ name: "attended" }))
  // Only the listing's operator, only the attended flag. The hook allows false -> true once the shift has started.
  signups.updateRule = `@request.auth.verified = true && @request.auth.role = "operator" && opportunity.operator = @request.auth.id` +
    ` && @request.body.attended:isset = true` +
    ["opportunity", "volunteer", "name", "email", "phone", "school", "grade"].map((f) => ` && @request.body.${f}:isset = false`).join("")
  app.save(signups)

  // The confirming operator's user id. Set only by the server; a student can never set it.
  // Plain text rather than a relation: if the organization later deletes its account, a relation would be
  // cleared and the student's confirmed hours would turn back into unsigned, editable ones.
  const hourLogs = app.findCollectionByNameOrId("hour_logs")
  hourLogs.fields.add(new TextField({ name: "confirmed_by", max: 50 }))
  hourLogs.createRule += LOG_CREATE_LOCK
  // Confirmed logs are locked like signed ones.
  hourLogs.updateRule += LOG_UPDATE_LOCK
  app.save(hourLogs)
}, (app) => {
  const signups = app.findCollectionByNameOrId("signups")
  signups.fields.removeByName("attended")
  signups.updateRule = null
  app.save(signups)

  const hourLogs = app.findCollectionByNameOrId("hour_logs")
  hourLogs.fields.removeByName("confirmed_by")
  hourLogs.createRule = hourLogs.createRule.replace(LOG_CREATE_LOCK, "")
  hourLogs.updateRule = hourLogs.updateRule.replace(LOG_UPDATE_LOCK, "")
  app.save(hourLogs)
})
