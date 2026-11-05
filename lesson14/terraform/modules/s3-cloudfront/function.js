// SPA fallback: a path whose last segment has no "." is a client-side route, so serve the app shell.
// Files (/_nuxt/app.js, /favicon.ico) pass through. Only the default behaviour runs this, so /api/* and /images/* are untouched.
function handler(event) {
  var request = event.request;
  var lastSegment = request.uri.split("/").pop();
  if (lastSegment.indexOf(".") === -1) {
    request.uri = "/index.html";
  }
  return request;
}
