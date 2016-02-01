import critbits
import strutils
import tables
from asynchttpserver import Request

#
#Type Declarations
#

const wildcard = '*'
const allowedUrlChars = {'a'..'z', 'A'..'Z', '0'..'9', '-', '.', '_', '~', '/', '?', '&', '='}
const allowedPatternChars = allowedUrlChars + {wildcard} #the star character is used for patterns

type
  Params* = Table[string, string]
  RequestHandler* = proc (req: Request, params: Params) : string {.gcsafe.}

  RoutingNode = ref object
    wildcards : CritBitTree[RoutingNode]
    leafHandler : RequestHandler
  Router* = RoutingNode

#
#Debugging Helper Procedures
#
proc nodeType(node : RoutingNode) : string =
  if node.leafHandler != nil:
    if node.wildcards.len() > 0:
      return "handler+container"
    else:
      return "handler"
  else:
    return "container"

proc printRoutingTree*(parentNode : RoutingNode, level : int = 0) =
  for path, childNode in parentNode.wildcards.pairs():
    echo("  ".repeat(level), path, " -> ", nodeType(childNode))
    if childNode.wildcards.len() > 0:
      printRoutingTree(childNode, level + 1)

#
#Constructor
#
proc newRouter*() : RoutingNode =
  return RoutingNode(leafHandler:nil, wildcards:CritBitTree[RoutingNode]())

#
#Procedures to add routes
#
proc route*(node : RoutingNode, pattern : string, handler : RequestHandler, level : int = 0) =
  assert(pattern.allCharsInSet(allowedPatternChars))
  let wildcardFirstIndex = pattern.find(wildcard)

  if wildcardFirstIndex == -1: #no wildcards
    if node.wildcards.contains(pattern):
      let subNode = node.wildcards[pattern]
      assert(subNode.leafHandler == nil)
      subNode.leafHandler = handler
    else:
      node.wildcards[pattern] = RoutingNode(leafHandler:handler, wildcards:CritBitTree[RoutingNode]())
  else: #parse to the first one, then recurse
    let prefix = pattern.substr(0, wildcardFirstIndex-1)
    let suffix = pattern.substr(wildcardFirstIndex+1)

    var subNode : RoutingNode

    if node.wildcards.contains(prefix):
      subNode = node.wildcards[prefix]
    else:
      subNode = RoutingNode(wildcards:CritBitTree[RoutingNode]())
      node.wildcards[prefix] = subNode

    subNode.route(suffix, handler, level + 1)

  if level == 0: echo "Created mapping for '", pattern, "'"

#
# Procedures to match against paths

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
