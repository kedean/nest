import src/router
import logging
import asynchttpserver, strtabs, times, asyncdispatch

type
  RequestHandler = proc (
    req: Request,
    headers : var StringTableRef,
    args : PathMatchingArgs
  ) : string {.gcsafe.}

let logger = newConsoleLogger()
let routing = newRouter(logger)
logger.log(lvlInfo, "****** Created server on ", getTime(), " ******")

# Set up mappings
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

# start up the server
let server = newAsyncHttpServer()
logger.log(lvlInfo, "****** Started server on ", getTime(), " ******")
proc dispatch(req: Request) {.async, gcsafe.} =
  let (statusCode, headers, content) = routing.route(req)
  await req.respond(statusCode, content, headers)
waitFor server.serve(Port(8080), dispatch)
