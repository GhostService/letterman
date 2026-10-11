/// <reference path="../pb_data/types.d.ts" />

// Which listing an hour log came from, when the student logged it from a shift they signed up for.
// The app uses it to stop offering "Log your hours" for that shift. Deleting the listing just clears it.

migrate((app) => {
  const hourLogs = app.findCollectionByNameOrId("hour_logs")
  const opportunities = app.findCollectionByNameOrId("opportunities")
  hourLogs.fields.add(new RelationField({ name: "opportunity", collectionId: opportunities.id, maxSelect: 1, cascadeDelete: false }))
  app.save(hourLogs)
}, (app) => {
  const hourLogs = app.findCollectionByNameOrId("hour_logs")
  hourLogs.fields.removeByName("opportunity")
  app.save(hourLogs)
})
