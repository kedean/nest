import src/router
import logging
import asynchttpserver, strtabs, times, asyncdispatch
import src/extractors

type
  RequestHandler = proc (
    req: Request,
    headers : var StringTableRef,
    args : PathMatchingArgs
  ) : string {.gcsafe.}

let logger = newConsoleLogger()
let routing = newRouter(logger)
logger.log(lvlInfo, "****** Created server on ", getTime(), " ******")

proc dispatch(req: Request) {.async, gcsafe.} =
  var
    statusCode : HttpCode
    content : string
    headers = newStringTable()

  try:
    let requestMethod = req.reqMethod
    let requestPath = req.url.path
    let queryString = req.url.query
    let requestHeaders = req.headers
    (statusCode, headers, content) = routing.route(req)

    if statusCode == Http404:
      logger.log(lvlError, "No mapping found for path '", requestPath, "' with method '", requestMethod, "'")
  except:
    logger.log(lvlError, "Internal error occured:\n\t", getCurrentExceptionMsg())
    statusCode = Http500
    content = "Internal server error"

  await req.respond(statusCode, content, headers)



proc root(
  req: Request,
  headers : var StringTableRef,
  args : PathMatchingArgs
) : string {.gcsafe.} =
  return "this is the root page"

routing.map(root, GET, "/")

proc parameterized(
  req: Request,
  headers : var StringTableRef,
  args : PathMatchingArgs
) : string {.gcsafe.} =
  return "you passed an argument: " & args.pathArgs.getOrDefault("test")

routing.map(parameterized, GET, "/{test}/foo")


let server = newAsyncHttpServer()
logger.log(lvlInfo, "****** Started server on ", getTime(), " ******")
waitFor server.serve(Port(8080), dispatch)
