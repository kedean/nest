import asynchttpserver, asyncdispatch
import router, extractors
import tables, strtabs
import logging
import times

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
    router: Router[RequestHandler]
    logger*: Logger

  RequestHandler = proc (req: Request, headers : var StringTableRef, pathParams : StringTableRef, queryParams : StringTableRef, modelParams : StringTableRef) : string {.gcsafe.}

const defaultLogFile = "nest.log"

proc newNestServer* (logger : Logger = newRollingFileLogger(defaultLogFile)) : NestServer =
  let routing = newRouter[RequestHandler]()
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
      let matchResult = routing.match(requestMethod, requestPath)

      case matchResult.status:
        of pathMatchNotFound:
          let fullPath = requestPath & (if queryString.len() > 0: "?" & queryString else: "")
          logger.log(lvlError, "No mapping found for path '", fullPath, "' with method '", requestMethod, "'")
          statusCode = Http404
          content = "Page not found"
        of pathMatchFound:
          let queryParams = queryString.extractQueryParams()
          let modelParams = req.body.extractFormBody(req.headers.getOrDefault("Content-Type"))
          statusCode = Http200
          content = matchResult.handler(req, headers, matchResult.pathParams, queryParams, modelParams)
    except:
      logger.log(lvlError, "Internal error occured:\n\t", getCurrentExceptionMsg())
      statusCode = Http500
      content = "Internal server error"

    await req.respond(statusCode, content, headers)

  return NestServer(
    httpServer: newAsyncHttpServer(),
    dispatchMethod: dispatch,
    router: routing,
    logger: logger
    )

proc run*(nest : NestServer, portNum : int) =
  nest.logger.log(lvlInfo, "****** Started server on ", getTime(), " ******")
  waitFor nest.httpServer.serve(Port(portNum), nest.dispatchMethod)

proc addRoute*(nest : NestServer, reqMethod : string, reqPath : string, handler : RequestHandler, reqHeaders : StringTableRef  = newStringTable()) =
  nest.router.route(reqMethod, reqPath, handler, reqHeaders, nest.logger)
