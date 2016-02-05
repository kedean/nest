import nest, logger
export nest

template onPort*(portNum, actions: untyped): untyped =
  ## Start up a server on the given port and make it available to templates
  let server {.inject.} = newNestServer()
  try:
    actions
    server.run(portNum)
  finally:
    discard

#
# Templates to simplify writing handlers
#

template map*(reqMethod, path, actions:untyped) : untyped =
  server.addRoute(reqMethod, path, proc (request:Request, responseHeaders : var StringTableRef, pathParams:StringTableRef, queryParams:StringTableRef, modelParams:StringTableRef) : string {.gcsafe.} =
    let request {.inject.} = request
    let responseHeaders {.inject.} = responseHeaders
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
  try:
    pathParams[key]
  except:
    log "No path parameter found called '", key, "'"
    ""
template queryParam*(key : string) : string =
  ## Safely gets a single parameter from the query string, or an empty string if it doesn't exist
  try:
    queryParams[key]
  except:
    log "No query parameter found called '", key, "'"
    ""
template modelParam*(key : string) : string =
  ## Safely gets a single parameter from the model, or an empty string if it doesn't exist
  try:
    modelParams[key]
  except:
    log "No model parameter found called '", key, "'"
    ""
template param*(key : string) : string =
  ## Safely gets a single parameter from the path, query string, or model, or an empty string if it doesn't exist. Path parameters take precedence, followed by query string parameters
  (if pathParams.hasKey(key): pathParams[key] elif queryParams.hasKey(key): queryParams[key] elif modelParams.hasKey(key): modelParams[key] else: log("No parameter found called '", key, "'"); "")

#
# Header management templates
#

template sendHeader*(key : string, value : string) =
  ## Add a new header to the response
  responseHeaders[key] = value
template getHeader*(key : string) : string =
  try:
    request.headers[key]
  except KeyError:
    log "No header found called '", key, "'"
    ""
