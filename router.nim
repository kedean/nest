import strutils, parseutils, strtabs, sequtils
import logging
import critbits
import URI

export URI, strtabs

#
#Type Declarations
#

const pathSeparator = '/'
const allowedCharsInUrl = {'a'..'z', 'A'..'Z', '0'..'9', '-', '.', '_', '~', pathSeparator}
const wildcard = '*'
const startParam = '{'
const endParam = '}'
const specialSectionStartChars = {pathSeparator, wildcard, startParam}
const allowedCharsInPattern = allowedCharsInUrl + {wildcard, startParam, endParam}

type

  HttpVerb* = enum
    GET = "get"
    HEAD = "head"
    OPTIONS = "options"
    PUT = "put"
    POST = "post"
    DELETE = "delete"

  PatternMatchingType = enum
    ptrnWildcard
    ptrnParam
    ptrnText
    ptrnStartHeaderConstraint
    ptrnEndHeaderConstraint

  # Structures for setting up the mappings
  MapperKnot = object
    case kind : PatternMatchingType:
      of ptrnParam, ptrnText:
        value : string
      of ptrnWildcard, ptrnEndHeaderConstraint:
        discard
      of ptrnStartHeaderConstraint:
        headerName : string
  MapperRope[H] = tuple
    pattern : seq[MapperKnot]
    handler : H

  MapperBundle[H] = ref object
    ropes : seq[MapperRope[H]]

  Mapper*[H] = ref object
    mappings : CritBitTree[MapperBundle[H]]
    logger : Logger

  # Structures for holding fully parsed mappings
  PatternNode[H] = ref object
    case kind : PatternMatchingType: # TODO: should be able to extend MapperKnot to get this, compiled wont let me, investigate further
      of ptrnParam, ptrnText:
        value : string
      of ptrnWildcard, ptrnEndHeaderConstraint:
        discard
      of ptrnStartHeaderConstraint:
        headerName : string
    case isLeaf : bool: #a leaf node is one with no children
      of true:
        discard
      of false:
        children : seq[PatternNode[H]]
    case isTerminator : bool: # a terminator is a node that can be considered a mapping on its own, matching could stop at this node or continue. If it is not a terminator, matching can only continue
      of true:
        handler : H
      of false:
        discard

  # Router Structures
  Router*[H] = ref object
    methodRouters : CritBitTree[PatternNode[H]]
    logger : Logger

  RoutingArgs* = object
    pathArgs* : StringTableRef
    queryArgs* : StringTableRef
    bodyArgs* : StringTableRef

  RoutingResultType* = enum
    pathMatchFound
    pathMatchNotFound
    pathMatchError
  RoutingResult*[H] = object
    case status* : RoutingResultType:
      of pathMatchFound:
        handler* : H
        arguments* : RoutingArgs
      of pathMatchNotFound:
        discard
      of pathMatchError:
        cause : ref Exception

  # Exceptions
  RoutingError = object of Exception
  MappingError = object of Exception

#
# Stringification
#
proc `$`(piece : MapperKnot) : string =
  case piece.kind:
    of ptrnParam, ptrnText:
      result = $(piece.kind) & ":" & piece.value
    of ptrnWildcard, ptrnEndHeaderConstraint:
      result = $(piece.kind)
    of ptrnStartHeaderConstraint:
      result = $(piece.kind) & ":" & piece.headerName
proc `$`[H](node : PatternNode[H]) : string =
  case node.kind:
    of ptrnParam, ptrnText:
      result = $(node.kind) & ":value=" & node.value & ", "
    of ptrnWildcard, ptrnEndHeaderConstraint:
      result = $(node.kind) & ":"
    of ptrnStartHeaderConstraint:
      result = $(node.kind) & ":" & node.headerName & ", "
  result = result & "leaf=" & $node.isLeaf & ", terminator=" & $node.isTerminator

#
# Constructors
#
proc newMapper*[H](logger : Logger = newConsoleLogger()) : Mapper[H] =
  return Mapper[H](
    mappings : CritBitTree[MapperBundle[H]](),
    logger: logger
  )

#
# Procedures to add initial mappings
#
proc emptyKnotSequence(
  knotSeq : seq[MapperKnot]
) : bool {.noSideEffect.} =
  ##
  ## A knot sequence is empty if it A) contains no elements or B) it contains a single text element with no value
  ##
  result = len(knotSeq) == 0 or (len(knotSeq) == 1 and knotSeq[0].kind == ptrnText and knotSeq[0].value == "")

proc generateRope(
  pattern : string,
  startIndex : int = 0
) : seq[MapperKnot] {.noSideEffect, raises: [MappingError].} =
  ##
  ## Translates the string form of a pattern into a sequence of MapperKnot objects to be parsed against
  ##
  var token : string
  let tokenSize = pattern.parseUntil(token, specialSectionStartChars, startIndex)
  var newStartIndex = startIndex + tokenSize

  if newStartIndex < pattern.len(): # we encountered a wildcard or parameter def, there could be more left
    let specialChar = pattern[newStartIndex]
    newStartIndex += 1

    var scanner : MapperKnot

    if specialChar == wildcard:
      scanner = MapperKnot(kind:ptrnWildcard)
    elif specialChar == startParam:
      var paramName : string
      let paramNameSize = pattern.parseUntil(paramName, endParam, newStartIndex)
      newStartIndex += (paramNameSize + 1)
      scanner = MapperKnot(kind:ptrnParam, value:paramName)
    elif specialChar == pathSeparator:
      scanner = MapperKnot(kind:ptrnText, value:($pathSeparator))
    else:
      raise newException(MappingError, "Unrecognized special character")

    var prefix : seq[MapperKnot]
    if tokenSize > 0:
      prefix = @[MapperKnot(kind:ptrnText, value:token),   scanner]
    else:
      prefix = @[scanner]

    let suffix = generateRope(pattern, newStartIndex)

    if emptyKnotSequence(suffix):
      return prefix
    else:
      return concat(prefix, suffix)

  else: #no more wildcards or parameter defs, the rest is static text
    result = newSeq[MapperKnot](len(token))
    for i, c in pairs(token):
      result[i] = MapperKnot(kind:ptrnText, value:($c))

proc map*[H](
  mapper : Mapper[H],
  handler : H,
  verb: HttpVerb,
  pattern : string,
  headers : StringTableRef = newStringTable()
) {.gcsafe.} =
  ##
  ## Add a new mapping to the given mapper instance
  ##

  if(not pattern.allCharsInSet(allowedCharsInPattern)):
    raise newException(MappingError, "Illegal characters occurred in the mapped pattern, please restrict to alphanumerics, or the following: - . _ ~ /")

  #if a url ends in a forward slash, we discard it and consider the matcher the same as without it
  var pattern = pattern
  pattern.removeSuffix('/')

  if not (pattern[0] == '/'): #ensure each pattern is relative to root
    pattern.insert("/")

  var bundle : MapperBundle[H]
  try:
    bundle = mapper.mappings[$verb]
  except KeyError:
    bundle = MapperBundle[H](ropes:newSeq[MapperRope[H]]())
    mapper.mappings[$verb] = bundle

  var rope = generateRope(pattern)

  if headers != nil:
    for key, value in headers:
      rope.add(MapperKnot(kind:ptrnStartHeaderConstraint, headerName:key))
      rope = concat(rope, generateRope(value))
      rope.add(MapperKnot(kind:ptrnEndHeaderConstraint))

  bundle.ropes.add((pattern:rope, handler:handler))

  #TODO: ensure the path does not conflict with an existing one
  mapper.logger.log(lvlInfo, "Created ", $verb, " mapping for '", pattern, "'")

#
# Data extractors and utilities
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

#
# Compression routines, compression makes matching more efficient, and it must be done before routing
#

proc knotToNode[H](rope : MapperRope[H], index : int, isLeaf : bool, isTerminator : bool) : PatternNode[H] {.noSideEffect.} =
  let knot = rope.pattern[index]

  case knot.kind:
    of ptrnText, ptrnParam:
      if isTerminator:
        result = PatternNode[H](kind: knot.kind, value: knot.value, isLeaf: isLeaf, isTerminator: true, handler: rope.handler)
      else:
        result = PatternNode[H](kind: knot.kind, value: knot.value, isLeaf: isLeaf, isTerminator: false)
    of ptrnWildcard, ptrnEndHeaderConstraint:
      if isTerminator:
        result = PatternNode[H](kind: knot.kind, isLeaf: isLeaf, isTerminator: true, handler: rope.handler)
      else:
        result = PatternNode[H](kind: knot.kind, isLeaf: isLeaf, isTerminator: false)
    of ptrnStartHeaderConstraint:
      if isTerminator:
        result = PatternNode[H](kind: knot.kind, headerName: knot.headerName, isLeaf: isLeaf, isTerminator: true, handler: rope.handler)
      else:
        result = PatternNode[H](kind: knot.kind, headerName: knot.headerName, isLeaf: isLeaf, isTerminator: false)


proc group[H](matchers : seq[MapperRope[H]], prefixCriteria : string = $(@[MapperKnot(kind:ptrnText, value:($pathSeparator))]), knotIndex : int = 0) : PatternNode[H] {.gcsafe.} =
  ##
  ## Create a node containing each knot that has the given criteria at the given knot index
  ##

  var critMatchIndices = newSeq[int]() # each entry indicates which element of matchers was matched with the criteria

  for matcherIndex, matcher in matchers.pairs():
    if len(matcher.pattern) > knotIndex: #we can only check this index of the matching sequence if its within the boundaries!
      let subseq = matcher.pattern[0..knotIndex]
      if $subseq == prefixCriteria:
        critMatchIndices.add(matcherIndex)

  case len(critMatchIndices):
    of 0: # should never happen
      raise newException(MappingError, "Invalid grouping state reached")
    of 1:
      let pattern = matchers[critMatchIndices[0]].pattern

      if len(pattern) - 1 == knotIndex: #this is the last knot in the rope
        result = knotToNode(rope = matchers[critMatchIndices[0]], index = knotIndex, isLeaf = true, isTerminator = true)
      else: #keep going!
        result = knotToNode(
          rope = matchers[critMatchIndices[0]],
          index = knotIndex,
          isLeaf = false,
          isTerminator = false
        )

        result.children = @[matchers.group($pattern[0..knotIndex+1], knotIndex + 1)]

    else:
      var terminatorRope : MapperRope[H]
      var terminatorRopeFound = false
      var knotsChecked = newSeq[string]()
      var children = newSeq[PatternNode[H]]()

      for matcherIndex in critMatchIndices:
        let pattern = matchers[matcherIndex].pattern

        if len(pattern) - 1 == knotIndex: #last node in the given sequence, this can only happen up to one time per critMatchIndices set
          assert terminatorRopeFound == false
          terminatorRope = matchers[matcherIndex]
          terminatorRopeFound = true
        else:
          let nextKnot = $pattern[knotIndex+1]
          if not knotsChecked.contains(nextKnot): #only have to do this one time
            knotsChecked.add(nextKnot)
            children.add(matchers.group($(pattern[0..knotIndex+1]), knotIndex + 1))

      if terminatorRopeFound:
        result = knotToNode(rope = terminatorRope, index = knotIndex, isLeaf = false, isTerminator = true)
      else:
        result = knotToNode(
          rope = matchers[critMatchIndices[0]], #does not matter which one we choose, ever matcher indicated by critMatchIndices should be identical if its not a terminator
          index = knotIndex,
          isLeaf = false,
          isTerminator = false
        )

      result.children = children

proc compress[H](node : PatternNode[H]) : PatternNode[H] =
  ##
  ## Finds sequences of single ptrnText nodes and combines them to reduce the depth of the tree
  ##
  if node.isLeaf: #if it's a leaf, there are clearly no descendents, and if it is a terminator then compression will alter the behavior
    return node
  elif node.kind == ptrnText and not node.isTerminator and len(node.children) == 1:
    let compressedChild = compress(node.children[0])
    if compressedChild.kind == ptrnText:
      result = compressedChild
      result.value = node.value & compressedChild.value
      return

  result = node
  result.children = map(result.children, compress)

proc newRouter*[H](mapper : Mapper[H]) : Router[H] =
  var methodRouters = CritBitTree[PatternNode[H]]()
  for key, bundle in pairs(mapper.mappings):
    methodRouters[key] = bundle.ropes.group().compress()
  result = Router[H](methodRouters:methodRouters, logger:mapper.logger)

#
# Debugging routines
#

proc printRoutingRope*[H](matchers : seq[MapperRope[H]]) =
  for matcher in matchers.items():
    for index, piece in matcher.pattern.pairs():
      if index != 0:
        write(stdout, " -> ")
      write(stdout, $piece)
    echo "\n"

proc printRoutingTree[H](node : PatternNode[H], tabs : int = 0) =
  echo ' '.repeat(tabs), $node
  if not node.isLeaf:
    for child in node.children:
      printRoutingTree(child, tabs + 1)

proc printMappings*[H](mapper : Mapper[H]) {.gcsafe.} =
  for verb, bundle in pairs(mapper.mappings):
    echo verb.toUpper()
    printRoutingRope(bundle.ropes)
proc printMappings*[H](router : Router[H]) {.gcsafe.} =
  for verb, tree in pairs(router.methodRouters):
    echo verb.toUpper()
    printRoutingTree(tree)


#
# Procedures to match against paths
#

proc matchTree[H](
  node : PatternNode[H],
  path : string,
  headers : StringTableRef,
  pathIndex : int = 0,
  scanningWildcard : bool = false,
  scanningParameter : bool = false,
  parameterBeingScanned : string = ""
) : RoutingResult[H] {.noSideEffect.} =
  ##
  ## Check whether the given path matches the given tree node starting from pathIndex
  ##
  var pathArgs = newStringTable()
  var pathIndex = pathIndex
  var scanningWildcard = scanningWildcard
  var scanningParameter = scanningParameter
  var parameterBeingScanned = parameterBeingScanned

  case node.kind:
    of ptrnText:
      if scanningWildcard or scanningParameter:
        if not path.contains(node.value):
          return RoutingResult[H](status:pathMatchNotFound)
        else: #skip forward til end of wildcard/param, then past the encountered text
          let paramEndIndex = path.find(node.value, pathIndex) - 1
          if paramEndIndex < 0:
            return RoutingResult[H](status:pathMatchNotFound)
          else:
            if scanningParameter:
              pathArgs[parameterBeingScanned] = path.substr(pathIndex, paramEndIndex)
            pathIndex = paramEndIndex + node.value.len() + 1
            scanningWildcard = false
            scanningParameter = false
      else:
        if path.continuesWith(node.value, pathIndex):
          pathIndex += node.value.len()
        else:
          return RoutingResult[H](status:pathMatchNotFound)
    of ptrnWildcard:
      assert(not scanningWildcard and not scanningParameter)
      scanningWildcard = true
    of ptrnParam:
      assert(not scanningWildcard and not scanningParameter)
      scanningParameter = true
      parameterBeingScanned = node.value
    of ptrnStartHeaderConstraint:
      for child in node.children:
        let childResult = child.matchTree(
          path=headers.getOrDefault(node.headerName),
          pathIndex=0,
          headers=headers
        )

        if childResult.status == pathMatchFound:
          for key, value in childResult.arguments.pathArgs:
            pathArgs[key] = value
          return RoutingResult[H](
            status:pathMatchFound,
            handler:childResult.handler,
            arguments:RoutingArgs(pathArgs:pathArgs)
          )
      return RoutingResult[H](status:pathMatchNotFound)
    of ptrnEndHeaderConstraint:
      if node.isTerminator and node.isLeaf:
        return RoutingResult[H](
          status:pathMatchFound,
          handler:node.handler,
          arguments:RoutingArgs(pathArgs:pathArgs)
        )

  if pathIndex == len(path) and node.isTerminator:
    return RoutingResult[H](
      status:pathMatchFound,
      handler:node.handler,
      arguments:RoutingArgs(pathArgs:pathArgs)
    )
#  elif pathIndex == len(path) and not node.isTerminator:
#    return RoutingResult[H](status:pathMatchNotFound)
  elif node.isLeaf:
    return RoutingResult[H](status:pathMatchNotFound)
  else:
    for child in node.children:
      let childResult = child.matchTree(
        path=path,
        headers=headers,
        pathIndex=pathIndex,
        scanningWildcard=scanningWildcard,
        scanningParameter=scanningParameter,
        parameterBeingScanned=parameterBeingScanned
      )

      if childResult.status == pathMatchFound:
        for key, value in childResult.arguments.pathArgs:
          pathArgs[key] = value
        return RoutingResult[H](
          status:pathMatchFound,
          handler:childResult.handler,
          arguments:RoutingArgs(pathArgs:pathArgs)
        )
    return RoutingResult[H](status:pathMatchNotFound)

proc route*[H](
  router : Router[H],
  requestMethod : string,
  requestUrl : URI,
  requestHeaders : StringTableRef,
  requestBody : string
) : RoutingResult[H] {.gcsafe.} =
  ##
  ## Find a mapping that matches the given request, and execute it's associated handler
  ##
  let logger = router.logger

  try:
    let verb = requestMethod.toLower()

    if router.methodRouters.hasKey(verb):
      result = matchTree(router.methodRouters[verb], trimPath(requestUrl.path), requestHeaders)

      if result.status == pathMatchFound:
        result.arguments.queryArgs = extractEncodedParams(requestUrl.query)
        result.arguments.bodyArgs = extractFormBody(requestBody, requestHeaders.getOrDefault("Content-Type"))
    else:
      result = RoutingResult[H](status:pathMatchNotFound)
  except:
    logger.log(lvlError, "Internal error occured:\n\t", getCurrentExceptionMsg())
    result = RoutingResult[H](status:pathMatchError, cause:getCurrentException())
