import nest
import strutils

onPort(8080):
  map("/", request):
    return """
    <html>
    <body>
    I am the root page
    <br/><br/>
    <a href="/leaf">Go to leaf page</a><br />
    <a href="/foo/bar">Go to page with wildcard</a><br />
    <a href="/parameterized/testParam">Go to page with path parameters</a><br />
    <a href="/queryString?test1=foo&test2=bar">Go to page with query parameters</a><br />
    </body>
    </html>
    """

  map("/leaf"):
    return """
    <html>
    <body>
    I am a leaf page
    <br/><br/>
    <a href="/">Go back</a>
    """

  map("/*/bar"):
    return """
    <html>
    <body>
    I used a wildcard path. Try changing the portion before "bar" to something else!
    <br/><br/>
    <a href="/">Go back</a>
    """

  map("/parameterized/{test}/", request, params):
    return """
    <html>
    <body>
    Your path param was $1. Try changing it to something else!
    <br/><br/>
    <a href="/">Go back</a>
    """.format(params.pathParams["test"])

  map("/queryString", request, params):
    return """
    <html>
    <body>
    Your query param 'test1' was '$1' and 'test2' was '$2'. Try changing it to something else!
    <br/><br/>
    <a href="/">Go back</a>
    """.format(params["test1"], params.queryParams.getOrDefault("test2"))

  echo "Starting server..."
