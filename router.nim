import critbits
import strutils
import parseutils
import sequtils
import tables
from asynchttpserver import Request

#
#Type Declarations
#

const allowedCharsInUrl = {'a'..'z', 'A'..'Z', '0'..'9', '-', '.', '_', '~', '/', '?', '&', '='}
const wildcard = '*'
const startParam = '{'
const endParam = '}'
const specialSectionStartChars = {wildcard, startParam}
const allowedCharsInPattern = allowedCharsInUrl + {wildcard, startParam, endParam}

type
  Params* = Table[string, string]
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

    let next = generatePatternSequence(pattern, newStartIndex)

    return concat(@[MatcherPiece(kind:matcherText, value:token), scanner], next)
  else:
    return @[MatcherPiece(kind:matcherText, value:token)]


proc route*(router : Router, pattern : string, handler : RequestHandler) =
  doAssert(pattern.allCharsInSet(allowedCharsInPattern))

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

proc match(router : Router, path : string) : RequestHandlerDef =
  if router.staticPaths.contains(path): #basic url, see if its in the list on its own first, guaranteed no conflicts with matcher characters
    return (handler: router.staticPaths[path], params: initTable[string, string]())
  else: #check for a match
    for matcher in router.pathMatchers:
      block checkMatch:
        var scanningWildcard, scanningParameter = false
        var parameterBeingScanned : string
        var pathIndex = 0
        var params = initTable[string, string]()

        for piece in matcher.pattern:
          echo piece.kind
          case piece.kind:
            of matcherText:
              if scanningWildcard or scanningParameter:
                if piece.value == "": #end of pieces to pattern, close out the scanning
                  if scanningParameter:
                    params[parameterBeingScanned] = path.substr(pathIndex)
                  scanningWildcard = false
                  scanningParameter = false
                elif not path.contains(piece.value):
                  break checkMatch
                else: #skip forward til end of wildcard, then past the encountered text
                  let paramEndIndex = path.find(piece.value, pathIndex) - 1
                  if scanningParameter:
                    params[parameterBeingScanned] = path.substr(pathIndex, paramEndIndex)
                  pathIndex = paramEndIndex + piece.value.len() + 1
                  scanningWildcard = false
                  scanningParameter = false
              else:
                if path.continuesWith(piece.value, pathIndex):
                  pathIndex += piece.value.len()
                else:
                  break checkMatch
            of matcherWildcard:
              scanningWildcard = true
            of matcherParam:
              scanningParameter = true
              parameterBeingScanned = piece.value

        if not scanningWildcard and not scanningParameter:
          return (handler:matcher.handler, params:params)





let r = newRouter()
r.route("/foo/{p}/bar/*/breh/{r}", proc (req: Request, params: Params) : string {.gcsafe.} = echo "test")
let (handler, params) = r.match("/foo/test/bar/pre/breh/d")
echo " "
echo params["p"]
echo params["r"]

when false:
  proc match*(node : RoutingNode, path : string) : RequestHandler {. noSideEffect .} #forward declaration
  proc checkWildcard(node : RoutingNode, path : string) : RequestHandler {. noSideEffect .}

  proc checkWildcard(node : RoutingNode, path : string) : RequestHandler =
    for matcher, childNode in node.wildcards.pairs():
      if path.endsWith(matcher): #perfect match
        return childNode.leafHandler
      elif path.contains(matcher): #partial match
        let wildcardEndIndex = path.find(matcher)
        let pathSuffix = path.substr(wildcardEndIndex) #everything after the part of the path this matches
        return childNode.match(pathSuffix)

  proc match(node : RoutingNode, path : string) : RequestHandler =
    if node.wildcards.contains(path): #see if there is a direct match first
      return node.wildcards[path].leafHandler
    else: ## now see if any of the wildcards will match. This is slower, since its guaranteed O(n)
      return node.checkWildcard(path)
