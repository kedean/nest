##
## Example of Nest extremely simple custom handlers. Nest makes no restrictions on the handler itself.
##
import nest
import asynchttpserver, asyncdispatch

#
# Initialization
#
let server = newAsyncHttpServer()
var mapper = newRouter[proc():string]()

mapper.map(
  proc () : string {.gcsafe.} = return "Hello World!"
  , $GET, "/")

mapper.compress()

let routerPtr = addr mapper

proc dispatch(req: Request) {.async, gcsafe.} =
  let result = routerPtr[].route(req.reqMethod, req.url, req.headers)

  if result.status == routingFailure:
    await req.respond(Http404, "Resource not found")
  else:
    var
      content : string
      statusCode : HttpCode
    try:
      content = result.handler()
      statusCode = Http200
    except:
      content = "Internal server error"
      statusCode = Http500

    await req.respond(statusCode, content)

waitFor server.serve(Port(8080), dispatch)
