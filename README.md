#Nest
RESTful API's with Nim

## Intro
This is an attempt at creating a framework for REST API's using [Nim](http://nim-lang.org). It is still in very early alpha stages.

## Is this usable?
Not at all. Check back soon.

## Coming soon
- parameterized mappings
- mappings for POST, HEAD, OPTION, DELETE, PUT, instead of just GET
- documentation!
- response editing?

## Usage
To use Nest, add an import to it to your code with `import nest`.

### Template based server
The preferred way to use Nest is with the provided templates: `onPort` and `map`. The `onPort` template takes the port number to server on as an argument, and provides the server to all code under its view. `map` will create a new route from the given path, and use the provided block as the handler. If a second parameter is provided, it is filled with the request context. If a third is provided, it contains a table of the URL parameters.

```nim
import nest

onPort(8080):
  get("/", request, parameters):
    return "this is the root page"
  get("/foo", request):
    return "this only took the request context"
  get("/bar"):
    return "this took no extra arguments"
```

Using the templates style means you don't have to worry about keeping track of your server, nor do you need to remember the syntax of a RequestHandler procedure.

### Procedural server
If you prefer to get down with the bare code, you can instantiate a server with `newNestServer`, then use the `addRoute` method to add new routes. You may use the asterisk ('*') as a wildcard character in your route definitions.

Example:
```nim
import nest

let server = newNestServer()

server.addRoute("/", nest.GET, (proc (req:Request, params:Params) : string =
  return "this is the root page"
))
server.addRoute("/*/foo", nest.GET, (proc (req:Request, params:Params) : string =
  return "this is a leaf page, generated with a wildcard"
))

echo "Starting server..."

server.run(8080)
```

### Accessing parameters
Named parameters may be specified in mappings with `{paramName}`. The params variable passed to the callback has two properties, `pathParams` and `queryParams`, both of which are implemented with Nim's [strtabs](http://nim-lang.org/docs/strtabs.html) module. It is suggested that you access parameters with `.getOrDefault(key : string)` to avoid exceptions. You may also use `params[key]` to safely get a parameter of either type, or an empty string if it is not found (path parameter take precedence over any conflicting query parameters). See example.nim for more.
