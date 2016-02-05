#Nest
RESTful API's with Nim

## Intro
This is an attempt at creating a framework for REST API's using [Nim](http://nim-lang.org). It is still in very early alpha stages.

## Is this usable?
Not at all. Check back soon.

## Coming soon
- cookie management
- content-type routing rules
- easier way to access request contents
- documentation!

## Usage
To use Nest, add an import to it to your code with `import nest`.

### Template based server
The preferred way to use Nest is with the provided templates: `onPort` and `map`. The `onPort` template takes the port number to server on as an argument, and provides the server to all code under its view. `map` will create a new route from the given path, and use the provided block as the handler. If a second parameter is provided, it is filled with the request context. If a third is provided, it contains a table of the URL parameters.

```nim
import nest

onPort(8080):
  get("/"):
    return "this is the root page"
```

Using the templates style means you don't have to worry about keeping track of your server, nor do you need to remember the syntax of a RequestHandler procedure.

### Procedural server
If you prefer to get down with the bare code, you can instantiate a server with `newNestServer`, then use the `addRoute` method to add new routes. You may use the asterisk ('*') as a wildcard character in your route definitions.

Example:
```nim
import nest

let server = newNestServer()

server.addRoute("/", nest.GET, (proc proc (req: Request, headers : var StringTableRef, pathParams : StringTableRef, queryParams : StringTableRef, modelParams : StringTableRef) : string =
  return "this is the root page"
))
server.addRoute("/*/foo", nest.GET, (proc proc (req: Request, headers : var StringTableRef, pathParams : StringTableRef, queryParams : StringTableRef, modelParams : StringTableRef) : string =
  return "this is a leaf page, generated with a wildcard"
))

echo "Starting server..."

server.run(8080)
```

### Accessing parameters
Named parameters may be accessed with the `param(key)` method, or more specifically with `pathParam(key)`, `queryParam(key)`, and `modelParam(key)`.

Headers may be sent and received with `getHeader(key)` and `sendHeader(key, value)`.
