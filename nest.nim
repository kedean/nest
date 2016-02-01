import asynchttpserver, asyncdispatch
import router

export Request

type
  NestServer = ref object
      httpServer: AsyncHttpServer
      dispatchMethod: proc (req:Request) : Future[void] {.closure, gcsafe.}
      router: Router


proc newNestServer* () : NestServer =
  let routing = newRouter()

  proc dispatch(req: Request) {.async.} =
    let requestPath = req.url.path
    let requestHandler = routing.match(requestPath)

    if requestHandler == nil:
      echo "No mapping found for path '", requestPath, "'"
      await req.respond(Http404, "Resource not found!")
    else:
      let content = requestHandler(req)
      await req.respond(Http200, content)

  return NestServer(
    httpServer: newAsyncHttpServer(),
    dispatchMethod: dispatch,
    router: routing
    )

proc run*(nest : NestServer, portNum : int) =
  waitFor nest.httpServer.serve(Port(portNum), nest.dispatchMethod)

proc addRoute*(nest : NestServer, requestPath : string, handler : RequestHandler) =
  nest.router.route(requestPath, handler)
