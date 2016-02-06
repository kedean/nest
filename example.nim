import src/nest_macros
import strutils

onPort(8080):
  get("/"):
    sendHeader("x-foo", "bar")
    return """
    <html>
    <body>
    I am the root page. Your user agent is '$1'!
    <br/><br/>
    <a href="/leaf">Go to leaf page</a><br />
    <a href="/foo/bar">Go to page with wildcard</a><br />
    <a href="/parameterized/testParam">Go to page with path parameters</a><br />
    <a href="/queryString?test1=foo&test2=bar">Go to page with query parameters</a><br />
    <a href="/form">Go to page with a POST form</a><br />
    </body>
    </html>
    """.format(getHeader("User-Agent"))

  get("/leaf"):
    return """
    <html>
    <body>
    I am a leaf page
    <br/><br/>
    <a href="/">Go back</a>
    """

  get("/form"):
    return """
    <html>
    <body>
    This is a form, try submitting it!
    <form method="POST" action="/form">
      <input type="text" name="field1" /><Br />
      <input type="text" name="field2" /><Br />
      <input type="submit" />
    </form>
    <br/><br />
    <a href="/">Go back</a>
    </body>
    </html>
    """

  post("/form"):
    return """
    <html>
    <body>
    You submitted a field1 value of '$1' and a field2 value of '$2'
    <br /><br />
    <a href="/">Go back</a>
    </body>
    </html>
    """.format(modelParam("field1"), modelParam("field2"))

  get("/*/bar"):
    return """
    <html>
    <body>
    I used a wildcard path. Try changing the portion before "bar" to something else!
    <br/><br/>
    <a href="/">Go back</a>
    """

  get("/parameterized/{test}/"):
    return """
    <html>
    <body>
    Your path param was $1. Try changing it to something else!
    <br/><br/>
    <a href="/">Go back</a>
    """.format(pathParam("test"))

  get("/queryString"):
    return """
    <html>
    <body>
    Your query param 'test1' was '$1' and 'test2' was '$2'. Try changing it to something else!
    <br/><br/>
    <a href="/">Go back</a>
    """.format(queryParam("test1"), queryParam("test2"))

  echo "Starting server..."
