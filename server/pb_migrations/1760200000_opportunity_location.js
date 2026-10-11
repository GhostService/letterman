/// <reference path="../pb_data/types.d.ts" />

// Map coordinates for each listing, picked from Apple Maps suggestions in the app, so students can
// filter opportunities by distance. The filtering itself happens on the phone. Not encrypted: listing
// addresses are already visible to every verified user.

migrate((app) => {
  const opportunities = app.findCollectionByNameOrId("opportunities")
  opportunities.fields.add(new NumberField({ name: "lat", min: -90, max: 90 }))
  opportunities.fields.add(new NumberField({ name: "lng", min: -180, max: 180 }))
  app.save(opportunities)
}, (app) => {
  const opportunities = app.findCollectionByNameOrId("opportunities")
  opportunities.fields.removeByName("lat")
  opportunities.fields.removeByName("lng")
  app.save(opportunities)
})
