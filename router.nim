import critbits
import strutils
import parseutils
import sequtils
import strtabs
from asynchttpserver import Request

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
  Params* = object
    pathParams* : StringTableRef
    queryParams* : StringTableRef

  RequestHandler* = proc (req: Request, params: Params) : string {.gcsafe.}
  RequestHandlerDef* = tuple[handler : RequestHandler, params : Params]

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
    handler : RequestHandler

  Router* = ref object
    staticPaths : CritBitTree[RequestHandler]
    pathMatchers : seq[PathMatcher]

proc `[]`*(params : Params, key : string) : string {.noSideEffect.} =
  ##[ Safely get a parameter of either kind, or the empty string if it does not exist. Path parameters take precedence over conflicting query parameters. ]##
  if params.pathParams.hasKey(key):
    return params.pathParams[key]
  elif params.queryParams.hasKey(key):
    return params.queryParams[key]
  else:
    return ""

#
#Constructor
#
proc newRouter*() : Router =
  return Router(pathMatchers:newSeq[PathMatcher](), staticPaths:CritBitTree[RequestHandler]())

#
#Procedures to add routes
#
proc generatePatternSequence(pattern : string, startIndex : int = 0) : seq[MatcherPiece] =
  var token : string
  let tokenSize = pattern.parseUntil(token, specialSectionStartChars, startIndex)
  var newStartIndex = startIndex + tokenSize

  if newStartIndex < pattern.len():
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
      doAssert(false, "Unrecognized special character") #TODO: handle this better?

    return concat(@[MatcherPiece(kind:matcherText, value:token), scanner], generatePatternSequence(pattern, newStartIndex))
  else:
    return @[MatcherPiece(kind:matcherText, value:token)]

proc route*(router : Router, pattern : string, handler : RequestHandler) =
  doAssert(pattern.allCharsInSet(allowedCharsInPattern))

  #if a url ends in a forward slash, we discard it and consider the matcher the same as without it
  var pattern = pattern
  pattern.removeSuffix('/')

  if not (pattern[0] == '/'): #ensure each pattern is relative to root
    pattern.insert("/")

  if pattern.allCharsInSet(allowedCharsInUrl): #static cases do not need to be matched against
    router.staticPaths[pattern] = handler
  else:
    router.pathMatchers.add((pattern:generatePatternSequence(pattern), handler:handler))

  #TODO: ensure the path does not conflict with an existing one
  echo "Created mapping for '", pattern, "'"

#
# Procedures to match against paths
#

proc parse(pattern, path : string) : Params =
  var token : string;
  var tokenSize = pattern.parseUntil(token, specialSectionStartChars)
  echo token, " ", tokenSize

proc extractQueryParams(query : string) : StringTableRef {.noSideEffect.} =
  var index = 0
  result = newStringTable()

  while index < query.len():
    var paramValuePair : string
    let pairSize = query.parseUntil(paramValuePair, '&', index)

    index += pairSize + 1

    let equalIndex = paramValuePair.find('=')

    if equalIndex == -1: #no equals, just a boolean "existance" variable
      result[paramValuePair] = "" #just insert a record into the param table to indicate that it exists
    else: #is a 'setter' parameter
      let paramName = paramValuePair.substr(0, equalIndex - 1)
      let paramValue = paramValuePair.substr(equalIndex + 1)
      result[paramName] = paramValue

  return result


proc match*(router : Router, path : string, query : string = "") : RequestHandlerDef {.noSideEffect.} =
  var path = path
  if path != "/": #the root string is special
    path.removeSuffix('/') #trailing slashes are considered redundant

  let queryParams = query.extractQueryParams()

  if router.staticPaths.contains(path): #basic url, see if its in the list on its own first, guaranteed no conflicts with matcher characters
    return (handler: router.staticPaths[path], params: Params(pathParams:newStringTable(), queryParams:queryParams))
  else: #check for a match
    for matcher in router.pathMatchers:
      block checkMatch: #a single run, this can be broken if anything checked doesn't match
        var scanningWildcard, scanningParameter = false
        var parameterBeingScanned : string
        var pathIndex = 0
        var pathParams = newStringTable()

        for piece in matcher.pattern:
          case piece.kind:
            of matcherText:
              if scanningWildcard or scanningParameter:
                if piece.value == "": #end of pieces to pattern, close out the scanning
                  if scanningParameter:
                    pathParams[parameterBeingScanned] = path.substr(pathIndex)
                  scanningWildcard = false
                  scanningParameter = false
                elif not path.contains(piece.value):
                  break checkMatch
                else: #skip forward til end of wildcard, then past the encountered text
                  let paramEndIndex = path.find(piece.value, pathIndex) - 1
                  if scanningParameter:
                    pathParams[parameterBeingScanned] = path.substr(pathIndex, paramEndIndex)
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

        if not scanningWildcard and not scanningParameter:
          return (handler:matcher.handler, params:Params(pathParams:pathParams, queryParams:queryParams))
