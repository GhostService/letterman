/// <reference path="../pb_data/types.d.ts" />

// Refuse to start without a valid encryption key, so personal data is never stored in plain text.
onBootstrap((e) => {
  require(`${__hooks}/lib.js`).key()
  e.next()
})

// ---- field encryption ----
// Encrypt right before the DB write (after validation), decrypt right before the API responds.
// Only readers that already passed the collection's API rules ever get a response.
onRecordCreateExecute((e) => {
  require(`${__hooks}/lib.js`).encryptRecord(e.record)
  e.next()
})

onRecordUpdateExecute((e) => {
  require(`${__hooks}/lib.js`).encryptRecord(e.record)
  e.next()
})

onRecordEnrich((e) => {
  require(`${__hooks}/lib.js`).decryptRecord(e.record)
  e.next()
})

// ---- hour logs: signature stamping ----
onRecordCreate((e) => {
  require(`${__hooks}/lib.js`).stampSignature(e.record)
  e.next()
}, "hour_logs")

onRecordUpdate((e) => {
  require(`${__hooks}/lib.js`).stampSignature(e.record)
  e.next()
}, "hour_logs")

// ---- opportunities: live "spots filled" count ----
// ponytail: one COUNT query per listed opportunity; fine for hundreds of listings,
// switch to a view collection if listing pages get slow.
onRecordEnrich((e) => {
  e.record.withCustomData(true)
  e.record.set("spots_filled", require(`${__hooks}/lib.js`).signupCount(e.app, e.record.id))
  e.next()
}, "opportunities")

onRecordUpdateRequest((e) => {
  const filled = require(`${__hooks}/lib.js`).signupCount(e.app, e.record.id)
  if (e.record.getInt("spots_needed") < filled) {
    throw new BadRequestError(`${filled} volunteers already signed up, so spots needed can't be lower than that.`)
  }
  e.next()
}, "opportunities")

// ---- signups: no overbooking + contact snapshot ----
onRecordCreateRequest((e) => {
  // Not a signed-in volunteer: let the collection's create rule reject it.
  if (!e.auth || e.auth.collection().name !== "users") return e.next()

  // The count and the insert run in one transaction. PocketBase serializes write transactions,
  // so two people can't both take the last spot.
  e.app.runInTransaction((txApp) => {
    const lib = require(`${__hooks}/lib.js`)
    let opp
    try {
      opp = txApp.findRecordById("opportunities", e.record.getString("opportunity"))
    } catch (_) {
      throw new BadRequestError("That opportunity doesn't exist anymore.")
    }
    if (opp.getDateTime("starts_at").before(new DateTime())) {
      throw new BadRequestError("This opportunity has already started.")
    }
    if (lib.signupCount(txApp, opp.id) >= opp.getInt("spots_needed")) {
      throw new BadRequestError("This opportunity is full.")
    }

    // Snapshot the volunteer's contact info for the operator (values stay encrypted as-is).
    for (const f of ["name", "phone", "school", "grade"]) {
      e.record.set(f, e.auth.getString(f))
    }
    e.record.set("email", e.auth.email())

    e.app = txApp
    e.next()
  })
}, "signups")
