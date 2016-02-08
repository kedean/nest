import src/router

import logging
import asynchttpserver, strtabs, times, asyncdispatch, math

let logger = newConsoleLogger()
logger.log(lvlInfo, "****** Created server on ", getTime(), " ******")

var
  routingRequests : Channel[Request]
  routingResponses : Channel[RoutingResult]
  thread : Thread[void]

proc routingThread {.thread.} =
  let logger = newConsoleLogger()
  let routing = newRouter(logger)
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

  while true:
    let request = routingRequests.recv()
    routingResponses.send(routing.route(request))

open routingRequests
open routingResponses

thread.createThread routingThread

# start up the server
let server = newAsyncHttpServer()
logger.log(lvlInfo, "****** Started server on ", getTime(), " ******")

proc dispatch(req: Request) {.async, gcsafe.} =
  # let (statusCode, headers, content) = routing.route(req)
  # await req.respond(statusCode, content, headers)
  let t1 = epochTime()
  routingRequests.send(req)
  let matchingResult = routingResponses.recv()
  let t2 = epochTime()
  echo "took ", ((t2 - t1) * 1000)

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
