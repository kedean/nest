import asynchttpserver, asyncdispatch
import router, extractors
import tables
import strtabs

export Request, tables, strtabs

type
  NestServer = ref object
      httpServer: AsyncHttpServer
      dispatchMethod: proc (req:Request) : Future[void] {.closure, gcsafe.}
      router: Router

proc newNestServer* () : NestServer =
  let routing = newRouter()

  proc dispatch(req: Request) {.async, gcsafe.} =
    let requestMethod = req.reqMethod
    let requestPath = req.url.path
    let queryString = req.url.query
    let (handler, pathParams) = routing.match(requestMethod, requestPath)
    let queryParams = queryString.extractQueryParams()

    if handler == nil:
      let fullPath = requestPath & (if queryString.len() > 0: "?" & queryString else: "")
      echo "No mapping found for path '", fullPath, "' with method '", requestMethod, "'"
      await req.respond(Http404, "Resource not found!")
    else:
      let content = handler(req, pathParams, queryParams)
      await req.respond(Http200, content)

  return NestServer(
    httpServer: newAsyncHttpServer(),
    dispatchMethod: dispatch,
    router: routing
    )

proc run*(nest : NestServer, portNum : int) =
  waitFor nest.httpServer.serve(Port(portNum), nest.dispatchMethod)

proc addRoute*(nest : NestServer, requestMethod : string, requestPath : string, handler : RequestHandler) =
  nest.router.route(requestMethod, requestPath, handler)

template onPort*(portNum, actions: untyped): untyped =
  let server {.inject.} = newNestServer()
  try:
    actions
    server.run(portNum)
  finally:
    discard

#
# Templates to simplify writing handlers
#

const
  GET* = "get"
  POST* = "post"
  HEAD* = "head"
  OPTIONS* = "options"
  PUT* = "put"
  DELETE* = "delete"

template get*(path, actions:untyped) : untyped =
  server.addRoute(GET, path, proc (request:Request, pathParams:StringTableRef, queryParams:StringTableRef) : string {.gcsafe.} =
    let request {.inject.} = request
    let pathParams {.inject.} = pathParams
    let queryParams {.inject.} = queryParams
    actions)

template post*(path, actions:untyped) : untyped =
  server.addRoute(POST, path, proc (request:Request, pathParams:StringTableRef, queryParams:StringTableRef) : string {.gcsafe.} =
    let request {.inject.} = request
    let pathParams {.inject.} = pathParams
    let queryParams {.inject.} = queryParams
    actions)

template head*(path, actions:untyped) : untyped =
  server.addRoute(HEAD, path, proc (request:Request, pathParams:StringTableRef, queryParams:StringTableRef) : string {.gcsafe.} =
    let request {.inject.} = request
    let pathParams {.inject.} = pathParams
    let queryParams {.inject.} = queryParams
    actions)

template options*(path, actions:untyped) : untyped =
  server.addRoute(OPTIONS, path, proc (request:Request, pathParams:StringTableRef, queryParams:StringTableRef) : string {.gcsafe.} =
    let request {.inject.} = request
    let pathParams {.inject.} = pathParams
    let queryParams {.inject.} = queryParams
    actions)

template put*(path, actions:untyped) : untyped =
  server.addRoute(PUT, path, proc (request:Request, pathParams:StringTableRef, queryParams:StringTableRef) : string {.gcsafe.} =
    let request {.inject.} = request
    let pathParams {.inject.} = pathParams
    let queryParams {.inject.} = queryParams
    actions)

template delete*(path, actions:untyped) : untyped =
  server.addRoute(DELETE, path, proc (request:Request, pathParams:StringTableRef, queryParams:StringTableRef) : string {.gcsafe.} =
    let request {.inject.} = request
    let pathParams {.inject.} = pathParams
    let queryParams {.inject.} = queryParams
    actions)

#
# Parameter extraction templates
#

template pathParam*(key : string) : string =
  pathParams.getOrDefault(key)
template queryParam*(key : string) : string =
  queryParams.getOrDefault(key)
template param*(key : string) : string =
  (if pathParams.hasKey(key): pathParams[key] elif queryParams.hasKey(key): queryParams[key] else: "")
