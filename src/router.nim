import strutils, parseutils, strtabs, sequtils
import logging
import critbits
from asynchttpserver import Request, HttpCode

#
#Type Declarations
#

const allowedCharsInUrl = {'a'..'z', 'A'..'Z', '0'..'9', '-', '.', '_', '~', '/'}
const wildcard = '*'
const startParam = '{'
const endParam = '}'
const specialSectionStartChars = {wildcard, startParam}
const allowedCharsInPattern = allowedCharsInUrl + {wildcard, startParam, endParam}

type
  RequestHandler = proc (
    req: Request,
    headers : var StringTableRef,
    args : PathMatchingArgs
  ) : string {.gcsafe.}

  HttpVerb* = enum
    GET = "get"
    HEAD = "head"
    OPTIONS = "options"
    PUT = "put"
    POST = "post"
    DELETE = "delete"

  MatcherPieceType = enum
    matcherWildcard,
    matcherParam,
    matcherText
  MatcherPiece = object
    case kind : MatcherPieceType:
      of matcherParam, matcherText:
        value : string
      of matcherWildcard:
        discard
  PathMatcher = tuple
    pattern : seq[MatcherPiece]
    headers : CritBitTree[seq[MatcherPiece]]
    handler : RequestHandler

  MethodRouter = ref object
    matchers : seq[PathMatcher]

  Router* = ref object
    methodRouters : CritBitTree[MethodRouter]
    logger : Logger

  RoutingError = object of Exception

  PathMatchingArgs* = object
    pathArgs* : StringTableRef
    queryArgs* : StringTableRef
    bodyArgs* : StringTableRef

  PathMatchingResultType = enum
    pathMatchFound
    pathMatchNotFound
  PathMatchingResult = object
    case status* : PathMatchingResultType:
      of pathMatchFound:
        handler* : RequestHandler
        arguments* : PathMatchingArgs
      of pathMatchNotFound:
        discard
  RequestMatchingResult* = tuple
    statusCode : HttpCode
    headers : StringTableRef
    content : string

#
# Constructors
#
proc newRouter*(logger : Logger = newConsoleLogger()) : Router =
  return Router(
    methodRouters : CritBitTree[MethodRouter](),
    logger: logger
  )

#
# Procedures to add mappings
#
proc generatePatternSequence(
  pattern : string,
  startIndex : int = 0
) : seq[MatcherPiece] {.noSideEffect, raises: [RoutingError].} =
  ##
  ## Translates the string form of a pattern into a sequence of MatcherPiece objects to be parsed against
  ##
  var token : string
  let tokenSize = pattern.parseUntil(token, specialSectionStartChars, startIndex)
  var newStartIndex = startIndex + tokenSize

  if newStartIndex < pattern.len(): # we encountered a wildcard or parameter def, there could be more left
    let specialChar = pattern[newStartIndex]
    newStartIndex += 1

    var scanner : MatcherPiece

    if specialChar == wildcard:
      scanner = MatcherPiece(kind:matcherWildcard)
    elif specialChar == startParam:
      var paramName : string
      let paramNameSize = pattern.parseUntil(paramName, endParam, newStartIndex)
      newStartIndex += (paramNameSize + 1)
      scanner = MatcherPiece(kind:matcherParam, value:paramName)
    else:
      raise newException(RoutingError, "Unrecognized special character")

    return concat(@[MatcherPiece(kind:matcherText, value:token), scanner], generatePatternSequence(pattern, newStartIndex))
  else: #no more wildcards or parameter defs, the rest is static text
    return @[MatcherPiece(kind:matcherText, value:token)]

proc map*(
  router : Router,
  handler : RequestHandler,
  verb: HttpVerb,
  pattern : string,
  headers : StringTableRef = newStringTable()
) {.gcsafe.} =
  ##
  ## Add a new mapping to the given router instance
  ##

  if(not pattern.allCharsInSet(allowedCharsInPattern)):
    raise newException(RoutingError, "Illegal characters occurred in the routing pattern, please restrict to alphanumerics, or the following: - . _ ~ /")

  #if a url ends in a forward slash, we discard it and consider the matcher the same as without it
  var pattern = pattern
  pattern.removeSuffix('/')

  if not (pattern[0] == '/'): #ensure each pattern is relative to root
    pattern.insert("/")

  var methodRouter : MethodRouter
  try:
    methodRouter = router.methodRouters[$verb]
  except KeyError:
    methodRouter = MethodRouter(matchers:newSeq[PathMatcher]())
    router.methodRouters[$verb] = methodRouter

  var matcherHeaders = CritBitTree[seq[MatcherPiece]]()
  if headers != nil:
    for key, value in headers:
      matcherHeaders[key] = generatePatternSequence(value)

  methodRouter.matchers.add((pattern:generatePatternSequence(pattern), headers: matcherHeaders, handler:handler))

  #TODO: ensure the path does not conflict with an existing one
  router.logger.log(lvlInfo, "Created ", $verb, " mapping for '", pattern, "'")

#
# Data extractors
#

proc extractEncodedParams(input : string) : StringTableRef {.noSideEffect.} =
  var index = 0
  result = newStringTable()

  while index < input.len():
    var paramValuePair : string
    let pairSize = input.parseUntil(paramValuePair, '&', index)

    index += pairSize + 1

    let equalIndex = paramValuePair.find('=')

    if equalIndex == -1: #no equals, just a boolean "existance" variable
      result[paramValuePair] = "" #just insert a record into the param table to indicate that it exists
    else: #is a 'setter' parameter
      let paramName = paramValuePair.substr(0, equalIndex - 1)
      let paramValue = paramValuePair.substr(equalIndex + 1)
      result[paramName] = paramValue

  return result

const FORM_URL_ENCODED = "application/x-www-form-urlencoded"
const FORM_MULTIPART_DATA = "multipart/form-data"

proc extractFormBody(body : string, contentType : string) : StringTableRef {.noSideEffect.} =
  if contentType.startsWith(FORM_URL_ENCODED):
    return body.extractEncodedParams()
  elif contentType.startsWith(FORM_MULTIPART_DATA):
    assert(false, "Multipart form data not yet supported")
  else:
    return newStringTable()

proc trimPath(path : string) : string {.noSideEffect.} =
  var path = path
  if path != "/": #the root string is special
    path.removeSuffix('/') #trailing slashes are considered redundant
  result = path

proc getErrorContent(verb : HttpCode, request : Request, logger : Logger) : string {.noSideEffect.} =
  ##
  ## Generates an error page for the given verb and request.
  ## TODO: This should be able to use user-defined error handlers too
  result = $verb

  if verb == Http404:
    logger.log(lvlError, "No mapping found for path '", request.url.path, "' with method '", request.reqMethod, "'")
  elif verb == Http500:
    logger.log(lvlError, "Internal server error occurred")

#
# Procedures to match against paths
#

proc matchPattern(pattern : seq[MatcherPiece], path : string) : PathMatchingResult {.noSideEffect.} =
  block checkMatch: #a single run, this can be broken if anything checked doesn't match
    var scanningWildcard, scanningParameter = false
    var parameterBeingScanned : string
    var pathIndex = 0
    var pathArgs = newStringTable()
    for piece in pattern:
      case piece.kind:
        of matcherText:
          if scanningWildcard or scanningParameter:
            if piece.value == "": #end of pieces to pattern, close out the scanning
              if scanningParameter:
                pathArgs[parameterBeingScanned] = path.substr(pathIndex)
              scanningWildcard = false
              scanningParameter = false
            elif not path.contains(piece.value):
              break checkMatch
            else: #skip forward til end of wildcard, then past the encountered text
              let paramEndIndex = path.find(piece.value, pathIndex) - 1
              if scanningParameter:
                pathArgs[parameterBeingScanned] = path.substr(pathIndex, paramEndIndex)
              pathIndex = paramEndIndex + piece.value.len() + 1
              scanningWildcard = false
              scanningParameter = false
          else:
            if path.continuesWith(piece.value, pathIndex):
              pathIndex += piece.value.len()
            else:
              break checkMatch
        of matcherWildcard:
          assert(not scanningWildcard and not scanningParameter)
          scanningWildcard = true
        of matcherParam:
          assert(not scanningWildcard and not scanningParameter)
          scanningParameter = true
          parameterBeingScanned = piece.value

    if not scanningWildcard and not scanningParameter and pathIndex == path.len():
      return PathMatchingResult(
        status:pathMatchFound,
        arguments:PathMatchingArgs(pathArgs:pathArgs)
      )
  return PathMatchingResult(status:pathMatchNotFound)

proc matchPath(matcher : PathMatcher, path : string, logger : Logger) : PathMatchingResult {.noSideEffect.} =
  let patternResult = matchPattern(matcher.pattern, path)
  case patternResult.status:
    of pathMatchFound:
      return PathMatchingResult(status:pathMatchFound, handler:matcher.handler, arguments:patternResult.arguments)
    of pathMatchNotFound:
      return PathMatchingResult(status:pathMatchNotFound)

proc matchHeaders(matcher : PathMatcher, headers : StringTableRef, logger : Logger) : PathMatchingResult =
  if (headers == nil or headers.len() == 0) and matcher.headers.len() == 0: #if all of the inputs are empty, no need to check them over
    return PathMatchingResult(status:pathMatchFound)

  for key, value in matcher.headers.pairs():
    let patternResult = matchPattern(value, headers.getOrDefault(key))
    if patternResult.status == pathMatchNotFound:
      logger.log(lvlError, "Could not match header called '", key, "' in request")
      return PathMatchingResult(status:pathMatchNotFound)
  return PathMatchingResult(status:pathMatchFound)

proc matchDynamic(pathMatchers : seq[PathMatcher], request : Request, logger : Logger) : PathMatchingResult {.noSideEffect.} =
  let path = trimPath(request.url.path)
  result = PathMatchingResult(status:pathMatchNotFound)

  for matcher in pathMatchers: # TODO: could this be sped up by using a CritBitTree and pairsWithPrefix?
    let pathResult = matcher.matchPath(path, logger)
    if pathResult.status == pathMatchFound:
      let headerResult = matcher.matchHeaders(request.headers, logger)
      if headerResult.status == pathMatchFound:
        return pathResult

proc route*(
  router : Router,
  request : Request
) : RequestMatchingResult {.gcsafe.} =
  ##
  ## Find a mapping that matches the given request, and execute it's associated handler
  ##
  let logger = router.logger

  try:
    let verb = request.reqMethod.toLower()

    if router.methodRouters.hasKey(verb):
      result = (statusCode: Http200, headers: newStringTable(), content: "")
      var matchingResult = matchDynamic(router.methodRouters[verb].matchers, request, logger)

      # actually call the handler, or 404
      case matchingResult.status:
        of pathMatchNotFound: # it's a 404!
          result = (statusCode: Http404, headers: newStringTable(), content: getErrorContent(Http404, request, logger))
        of pathMatchFound:
          matchingResult.arguments.queryArgs = extractEncodedParams(request.url.query)
          matchingResult.arguments.bodyArgs = extractFormBody(request.body, request.headers.getOrDefault("Content-Type"))

          result.content = matchingResult.handler(request, result.headers, matchingResult.arguments)
    else:
      result = (statusCode: Http405, headers: newStringTable(), content: getErrorContent(Http405, request, logger))
  except:
    logger.log(lvlError, "Internal error occured:\n\t", getCurrentExceptionMsg())
    result = (statusCode: Http500, headers: newStringTable(), content: getErrorContent(Http500, request, logger))


#
# Mapping macros
#
