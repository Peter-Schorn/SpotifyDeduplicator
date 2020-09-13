# SpotifyDeduplicator

This iOS app removes duplicate tracks from your Spotify playlists. To compile it, go to https://developer.spotify.com/dashboard/login and create an app. Take note of the client id and client secret. Then click on "edit settings" and add the following redirect URI:
```
peter-schorn-spotify-deduplicator://login-callback
```

Next, add `client_id` and `client_secret` to the environment variables for your scheme:

<a href="https://ibb.co/mtwMCRP"><img src="https://i.ibb.co/ZKPk6fb/Screen-Shot-2020-09-12-at-10-34-15-PM.png" alt="Screen-Shot-2020-09-12-at-10-34-15-PM" border="0"></a><br /><a target='_blank' href='https://imgbb.com/'>photos upload website</a><br />

You are encouraged to use the Spotify desktop application for testing the app. Interestingly, the order that the playlists are returned in by the Spotify web API matches the order that they are displayed in the sidebar of the desktop application. If you drag to reorder them, this will immediately affect the order that the API returns them in and the order that they are displayed in this app.

This app makes extensive use of playlist [snapshot ids][1]. Everytime a playlist changes, its snapshot id changes. This allows for efficiently determining whether a playlist has changed since the last time it was retrieved from the web API.

[1]: https://developer.spotify.com/documentation/general/guides/working-with-playlists/#version-control-and-snapshots
