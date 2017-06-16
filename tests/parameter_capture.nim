import unittest, uri, httpcore
import nest

suite "Parameter Capture":
  proc testHandler() = echo "test"

  test "One query string parameter":
    let r = newRouter[proc()]()
    r.map(testHandler, $GET, "/")
    let result = r.route("GET", parseUri("/?param1=value1"))
    check(result.status == routingSuccess)
    check(result.arguments.queryArgs.hasKey("param1"))
    check(result.arguments.queryArgs["param1"] == "value1")

  test "Many query string parameters":
    let r = newRouter[proc()]()
    r.map(testHandler, $GET, "/")
    let result = r.route("GET", parseUri("/?param1=value1&param2=value2"))
    check(result.status == routingSuccess)
    check(result.arguments.queryArgs.hasKey("param1"))
    check(result.arguments.queryArgs["param1"] == "value1")
    check(result.arguments.queryArgs.hasKey("param2"))
    check(result.arguments.queryArgs["param2"] == "value2")

  test "Boolean query parameter":
    let r = newRouter[proc()]()
    r.map(testHandler, $GET, "/")
    let result = r.route("GET", parseUri("/?param1=value1&param2"))
    check(result.status == routingSuccess)
    check(result.arguments.queryArgs.hasKey("param1"))
    check(result.arguments.queryArgs["param1"] == "value1")
    check(result.arguments.queryArgs.hasKey("param2"))

  test "Query param plus headers":
    let r = newRouter[proc()]()
    r.map(testHandler, $GET, "/", newHttpHeaders({"content-type": "text/plain"}))
    let result = r.route("GET", parseUri("/?param1=value1"), newHttpHeaders({"content-type": "text/plain"}))
    check(result.status == routingSuccess)
    check(result.arguments.queryArgs.hasKey("param1"))
    check(result.arguments.queryArgs["param1"] == "value1")

  test "Query and path params at the same time":
    let r = newRouter[proc()]()
    r.map(testHandler, $GET, "/{pathParam1}")
    let result = r.route("GET", parseUri("/pathVal?queryParam1=queryVal"))
    check(result.status == routingSuccess)
    check(result.arguments.queryArgs.hasKey("queryParam1"))
    check(result.arguments.queryArgs["queryParam1"] == "queryVal")
    check(result.arguments.pathArgs.hasKey("pathParam1"))
    check(result.arguments.pathArgs["pathParam1"] == "pathVal")

  test "Path param that consumes entire path":
    let r = newRouter[proc()]()
    r.map(testHandler, $GET, "/{pathParam1}$")
    let result = r.route("GET", parseUri("/foo/bar/baz"))
    check(result.status == routingSuccess)
    check(result.arguments.pathArgs.hasKey("pathParam1"))
    check(result.arguments.pathArgs["pathParam1"] == "foo/bar/baz")

  test "Path param combined with consuming path param":
    let r = newRouter[proc()]()
    r.map(testHandler, $GET, "/{pathParam1}/{pathParam2}$")
    let result = r.route("GET", parseUri("/foo/bar/baz"))
    check(result.status == routingSuccess)
    check(result.arguments.pathArgs.hasKey("pathParam1"))
    check(result.arguments.pathArgs["pathParam1"] == "foo")
    check(result.arguments.pathArgs.hasKey("pathParam2"))
    check(result.arguments.pathArgs["pathParam2"] == "bar/baz")

  test "Path param combined with consuming wildcard":
    let r = newRouter[proc()]()
    r.map(testHandler, $GET, "/{pathParam1}/*$")
    let result = r.route("GET", parseUri("/foo/bar/baz"))
    check(result.status == routingSuccess)
    check(result.arguments.pathArgs.hasKey("pathParam1"))
    check(result.arguments.pathArgs["pathParam1"] == "foo")
