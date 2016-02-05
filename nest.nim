import asynchttpserver, asyncdispatch
import router, extractors, logger
import tables
import strtabs

export Request, tables, strtabs

const
  GET* = "get"
  POST* = "post"
  HEAD* = "head"
  OPTIONS* = "options"
  PUT* = "put"
  DELETE* = "delete"

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
      headers = newStringTable()

    try:
      let requestMethod = req.reqMethod
      let requestPath = req.url.path
      let queryString = req.url.query
      let (handler, pathParams) = routing.match(requestMethod, requestPath)
      let queryParams = queryString.extractQueryParams()
      let modelParams = req.body.extractFormBody(req.headers.getOrDefault("Content-Type"))

      if handler == nil:
        let fullPath = requestPath & (if queryString.len() > 0: "?" & queryString else: "")
        log "No mapping found for path '", fullPath, "' with method '", requestMethod, "'"
        statusCode = Http404
        content = "Page not found"
      else:
        statusCode = Http200
        content = handler(req, headers, pathParams, queryParams, modelParams)
    except:
      log "Internal error occured:\n\t", getCurrentExceptionMsg()
      statusCode = Http500
      content = "Internal server error"

    await req.respond(statusCode, content, headers)

  return NestServer(
    httpServer: newAsyncHttpServer(),
    dispatchMethod: dispatch,
    router: routing
    )

proc run*(nest : NestServer, portNum : int) =
  waitFor nest.httpServer.serve(Port(portNum), nest.dispatchMethod)

proc addRoute*(nest : NestServer, reqMethod : string, reqPath : string, handler : RequestHandler) =
  nest.router.route(reqMethod, reqPath, handler)
  log "Created ", reqMethod, " mapping for '", reqPath, "'"
