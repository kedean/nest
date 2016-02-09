import src/router

import logging
import asynchttpserver, strtabs, times, asyncdispatch, math

type
  RequestHandler* = proc (
    req: Request,
    headers : var StringTableRef,
    args : RoutingArgs
  ) : string {.gcsafe.}

let logger = newConsoleLogger()
logger.log(lvlInfo, "****** Created server on ", getTime(), " ******")

var routing = newRouter[RequestHandler](logger)
let iterations = 100

for i in 0..iterations:
  routing.map(proc (
      req: Request,
      headers : var StringTableRef,
      args : RoutingArgs
    ) : string {.gcsafe.} =
      return "you passed an argument: " & args.pathArgs.getOrDefault("test")
    , GET, "/{test}/" & $i)

logger.log(lvlInfo, "****** Compressing routing tree ******")
compress(routing)

let routerPtr = addr routing

# start up the server
let server = newAsyncHttpServer()
logger.log(lvlInfo, "****** Started server on ", getTime(), " ******")

proc dispatch(req: Request) {.async, gcsafe.} =
  let matchingResult = routerPtr[].route(req.reqMethod, req.url, req.headers, req.body)

  if matchingResult.status == pathMatchNotFound:
    await req.respond(Http404, "Resource not found")
  elif matchingResult.status == pathMatchError:
    await req.respond(Http500, "Internal server error")
  else:
    var
      statusCode : HttpCode
      headers = newStringTable()
      content : string
    try:
      content = matchingResult.handler(req, headers, matchingResult.arguments)
      statusCode = Http200
    except:
      content = "Internal server error"
      statusCode = Http500

    await req.respond(statusCode, content, headers)

waitFor server.serve(Port(8080), dispatch)
