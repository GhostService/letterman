/// <reference path="../pb_data/types.d.ts" />

// The app was renamed from "Hour Tracker" to "Letterman". Fresh installs already get the new
// name from the init migration; this updates servers that were set up before the rename.
// The name appears in verification and password-reset emails.
migrate((app) => {
  const settings = app.settings()
  if (settings.meta.appName === "Hour Tracker") {
    settings.meta.appName = "Letterman"
    app.save(settings)
  }
}, (app) => {
  const settings = app.settings()
  if (settings.meta.appName === "Letterman") {
    settings.meta.appName = "Hour Tracker"
    app.save(settings)
  }
})
