import src/router
import logging
import asynchttpserver, strtabs, times, asyncdispatch, math

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

let iterations = 100

for i in 0..iterations:
  routing.map(proc (
      req: Request,
      headers : var StringTableRef,
      args : PathMatchingArgs
    ) : string {.gcsafe.} =
      return "you passed an argument: " & args.pathArgs.getOrDefault("test")
    , GET, "/{test}/" & $i)

logger.log(lvlInfo, "****** Compressing routing tree ******")
compress(routing)

# start up the server
let server = newAsyncHttpServer()
logger.log(lvlInfo, "****** Started server on ", getTime(), " ******")
proc dispatch(req: Request) {.async, gcsafe.} =
  let startT = epochTime()
  let (statusCode, headers, content) = routing.route(req)
  let endT = epochTime()
  echo req.url.path, ",", ceil((endT - startT) * 1000000)
  await req.respond(statusCode, content, headers)

waitFor server.serve(Port(8080), dispatch)
