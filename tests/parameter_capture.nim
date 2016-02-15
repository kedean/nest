import unittest, uri
import router

suite "Parameter Capture":
  proc testHandler() = echo "test"

  test "One query string parameter":
    let r = newRouter[proc()]()
    r.map(testHandler, GET, "/")
    let result = r.route("GET", parseUri("/?param1=value1"))
    check(result.status == routingSuccess)
    check(result.arguments.queryArgs.hasKey("param1"))
    check(result.arguments.queryArgs["param1"] == "value1")

  test "Many query string parameters":
    let r = newRouter[proc()]()
    r.map(testHandler, GET, "/")
    let result = r.route("GET", parseUri("/?param1=value1&param2=value2"))
    check(result.status == routingSuccess)
    check(result.arguments.queryArgs.hasKey("param1"))
    check(result.arguments.queryArgs["param1"] == "value1")
    check(result.arguments.queryArgs.hasKey("param2"))
    check(result.arguments.queryArgs["param2"] == "value2")

  test "Boolean query parameter":
    let r = newRouter[proc()]()
    r.map(testHandler, GET, "/")
    let result = r.route("GET", parseUri("/?param1=value1&param2"))
    check(result.status == routingSuccess)
    check(result.arguments.queryArgs.hasKey("param1"))
    check(result.arguments.queryArgs["param1"] == "value1")
    check(result.arguments.queryArgs.hasKey("param2"))

  test "Query param plus headers":
    let r = newRouter[proc()]()
    r.map(testHandler, GET, "/", newStringTable("content-type", "text/plain", modeCaseInsensitive))
    let result = r.route("GET", parseUri("/?param1=value1"), newStringTable("content-type", "text/plain", modeCaseInsensitive))
    check(result.status == routingSuccess)
    check(result.arguments.queryArgs.hasKey("param1"))
    check(result.arguments.queryArgs["param1"] == "value1")

  test "Query and path params at the same time":
    let r = newRouter[proc()]()
    r.map(testHandler, GET, "/{pathParam1}")
    let result = r.route("GET", parseUri("/pathVal?queryParam1=queryVal"))
    check(result.status == routingSuccess)
    check(result.arguments.queryArgs.hasKey("queryParam1"))
    check(result.arguments.queryArgs["queryParam1"] == "queryVal")
    check(result.arguments.pathArgs.hasKey("pathParam1"))
    check(result.arguments.pathArgs["pathParam1"] == "pathVal")
