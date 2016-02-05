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
    var
      statusCode : HttpCode
      content : string

    try:
      let requestMethod = req.reqMethod
      let requestPath = req.url.path
      let queryString = req.url.query
      let (handler, pathParams) = routing.match(requestMethod, requestPath)
      let queryParams = queryString.extractQueryParams()
      let modelParams = req.body.extractFormBody(req.headers.getOrDefault("Content-Type"))

      if handler == nil:
        let fullPath = requestPath & (if queryString.len() > 0: "?" & queryString else: "")
        echo "No mapping found for path '", fullPath, "' with method '", requestMethod, "'"
        statusCode = Http404
        content = "Page not found"
      else:
        statusCode = Http200
        content = handler(req, pathParams, queryParams, modelParams)
    except:
      statusCode = Http500
      content = "Server error"
      #TODO: Log the error

    await req.respond(statusCode, content)

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

template map*(reqMethod, path, actions:untyped) : untyped =
  server.addRoute(reqMethod, path, proc (request:Request, pathParams:StringTableRef, queryParams:StringTableRef, modelParams:StringTableRef) : string {.gcsafe.} =
    let request {.inject.} = request
    let pathParams {.inject.} = pathParams
    let queryParams {.inject.} = queryParams
    let modelParams {.inject.} = modelParams
    actions)

template get*(path, actions:untyped) : untyped =
  map(GET, path, actions)

template post*(path, actions:untyped) : untyped =
  map(POST, path, actions)

template head*(path, actions:untyped) : untyped =
  map(HEAD, path, actions)

template options*(path, actions:untyped) : untyped =
  map(OPTIONS, path, actions)

template put*(path, actions:untyped) : untyped =
  map(PUT, path, actions)

template delete*(path, actions:untyped) : untyped =
  map(DELETE, path, actions)

#
# Parameter extraction templates
#

template pathParam*(key : string) : string =
  ## Safely gets a single parameter from the path, or an empty string if it doesn't exist
  pathParams.getOrDefault(key)
template queryParam*(key : string) : string =
  ## Safely gets a single parameter from the query string, or an empty string if it doesn't exist
  queryParams.getOrDefault(key)
template modelParam*(key : string) : string =
  ## Safely gets a single parameter from the model, or an empty string if it doesn't exist
  modelParams.getOrDefault(key)
template param*(key : string) : string =
  ## Safely gets a single parameter from the path, query string, or model, or an empty string if it doesn't exist. Path parameters take precedence, followed by query string parameters
  (if pathParams.hasKey(key): pathParams[key] elif queryParams.hasKey(key): queryParams[key] elif modelParams.hasKey(key): modelParams[key] else: "")
