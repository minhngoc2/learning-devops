// Images live in the bucket as products/<file>, but viewers ask for /images/products/<file>.
// Only the /images/* behaviour runs this, so it strips exactly the leading "/images" before the S3 request.
function handler(event) {
  var request = event.request;
  if (request.uri.indexOf("/images/") === 0) {
    request.uri = request.uri.substring("/images".length);
  }
  return request;
}
