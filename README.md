#Nest
RESTful API's with Nim

## Intro
This is an attempt at creating a framework for REST API's using [Nim](http://nim-lang.org). It is still in very early alpha stages.

## Usage
To use Nest, add an import to it to your code with `import nest`. Instantiate a server with `newNestServer`, then use the `addRoute` method to add new routes. You may use the asterisk ('*') as a wildcard character in your route definitions.

Example:
```nim
import nest

let server = newNestServer()

server.addRoute("/", (proc (req:Request) : string =
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
))
server.addRoute("/leaf", (proc (req:Request) : string =
  return """
  <html>
  <body>
  I am a leaf page
  <br/><br/>
  <a href="/">Go back</a>
  """
))
server.addRoute("/*/bar", (proc (req:Request) : string =
  return """
  <html>
  <body>
  I used a wildcard path. Try changing "foo" to something else!
  <br/><br/>
  <a href="/">Go back</a>
  """
))

echo "Starting server..."

server.run(8080)
```
