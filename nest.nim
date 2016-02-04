import asynchttpserver, asyncdispatch
import router
import tables

export Request, Params, tables

type
  NestServer = ref object
      httpServer: AsyncHttpServer
      dispatchMethod: proc (req:Request) : Future[void] {.closure, gcsafe.}
      router: Router


proc newNestServer* () : NestServer =
  let routing = newRouter()

  proc dispatch(req: Request) {.async, gcsafe.} =
    let requestPath = req.url.path
    let (handler, params) = routing.match(requestPath)

    if handler == nil:
      echo "No mapping found for path '", requestPath, "'"
      await req.respond(Http404, "Resource not found!")
    else:
      let content = handler(req, params)
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

template onPort*(portNum, actions: untyped): untyped =
  let server {.inject.} = newNestServer()
  try:
    actions
    server.run(portNum)
  finally:
    discard

template map*(path, actions:untyped) : untyped =
  server.addRoute(path, proc (request:Request, params:Params) : string {.gcsafe.} = actions)
template map*(path, request, actions:untyped) : untyped =
  server.addRoute(path, proc (request:Request, params:Params) : string {.gcsafe.} = actions)
template map*(path, request, params, actions:untyped) : untyped =
  server.addRoute(path, proc (request:Request, params:Params) : string {.gcsafe.} = actions)
