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
    <a href="/parameterized/testParam">Go to page with parameters</a><br />
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

  map("/parameterized/{test}", request, params):
    return """
    <html>
    <body>
    Your param was $1. Try changing it to something else!
    <br/><br/>
    <a href="/">Go back</a>
    """.format(params["test"])

  echo "Starting server..."
