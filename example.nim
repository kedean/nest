import nest

onPort(8080):
  map("/", request):
    return """
    <html>
    <body>
    I am the root page
    <br/><br/>
    <a href="/leaf">Go to leaf page</a><br />
    <a href="/foo/bar">Go to page with wildcard</a>
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
    I used a wildcard path. Try changing "foo" to something else!
    <br/><br/>
    <a href="/">Go back</a>
    """

  echo "Starting server..."
