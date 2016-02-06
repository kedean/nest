import strtabs, parseutils, strutils

proc extractQueryParams*(query : string) : StringTableRef {.noSideEffect.} =
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

const FORM_URL_ENCODED = "application/x-www-form-urlencoded"
const FORM_MULTIPART_DATA = "multipart/form-data"

proc extractFormBody*(body : string, contentType : string) : StringTableRef {.gcsafe.} =
  if contentType.startsWith(FORM_URL_ENCODED):
    return body.extractQueryParams()
  elif contentType.startsWith(FORM_MULTIPART_DATA):
    assert(false, "Multipart form data not yet supported")
  else:
    return newStringTable()
