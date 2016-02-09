import src/router

import logging
import asynchttpserver, strtabs, times, asyncdispatch, math

type
  RequestHandler* = proc (
    req: Request,
    headers : var StringTableRef,
    args : RoutingArgs
  ) : string {.gcsafe.}

#
# Initialization
#
let logger = newConsoleLogger()
let server = newAsyncHttpServer()
logger.log(lvlInfo, "****** Created server on ", getTime(), " ******")

#
# Set up mappings
#
var mapper = newMapper[RequestHandler](logger)

mapper.map(proc (
    req: Request,
    headers : var StringTableRef,
    args : RoutingArgs
  ) : string {.gcsafe.} =
    return "you passed an argument: " & args.pathArgs.getOrDefault("test")
  , GET, "/{test}/foobar")

mapper.map(proc (
    req: Request,
    headers : var StringTableRef,
    args : RoutingArgs
  ) : string {.gcsafe.} =
    return "You must be on localhost!"
  , GET, "/")

logger.log(lvlInfo, "****** Compressing routing tree ******")
var routes = newRouter(mapper)

#
# Set up the dispatcher
#
let routerPtr = addr routes

proc dispatch(req: Request) {.async, gcsafe.} =
  ##
  ## Figures out what handler to call, and calls it
  ##
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

# start up the server
logger.log(lvlInfo, "****** Started server on ", getTime(), " ******")
waitFor server.serve(Port(8080), dispatch)
