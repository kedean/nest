import unittest, uri, httpcore
import nest

suite "Header Mapping":
  proc testHandler() = echo "test"

  test "Root with content-type header":
    let r = newRouter[proc()]()
    r.map(testHandler, $GET, "/", newHttpHeaders({"content-type": "text/plain"}))
    let goodResult = r.route("GET", parseUri("/"), newHttpHeaders({"content-type": "text/plain"}))
    check(goodResult.status == routingSuccess)
    let badResult = r.route("GET", parseUri("/"), newHttpHeaders({"content-type": "text/html"}))
    check(badResult.status == routingFailure)

  test "Parameterized with content-type header":
    let r = newRouter[proc()]()
    r.map(testHandler, $GET, "/test/{param1}", newHttpHeaders({"content-type": "text/plain"}))
    let goodResult = r.route("GET", parseUri("/test/foo"), newHttpHeaders({"content-type": "text/plain"}))
    check(goodResult.status == routingSuccess)
    let badResult = r.route("GET", parseUri("/test/foo"), newHttpHeaders({"content-type": "text/html"}))
    check(badResult.status == routingFailure)

  test "Root with multiple header constraints":
    let r = newRouter[proc()]()
    r.map(
      testHandler,
      $GET,
      "/",
      newHttpHeaders({
        "host": "localhost",
        "content-type": "text/plain"
      })
    )
    let goodResult = r.route("GET", parseUri("/"), newHttpHeaders({"content-type": "text/plain", "host": "localhost"}))
    check(goodResult.status == routingSuccess)
    let wrongContentType = r.route("GET", parseUri("/"), newHttpHeaders({"content-type": "text/html", "host": "localhost"}))
    check(wrongContentType.status == routingFailure)
    let wrongHost = r.route("GET", parseUri("/"), newHttpHeaders({"content-type": "text/plain", "host": "127.0.0.1"}))
    check(wrongHost.status == routingFailure)

  test "Header constraints don't conflict with other mappings":
    let r = newRouter[proc()]()
    r.map(testHandler, $GET, "/constrained", newHttpHeaders({"content-type": "text/plain"}))
    r.map(testHandler, $GET, "/unconstrained")

    let constrainedRouteWithHeader = r.route("GET", parseUri("/constrained"), newHttpHeaders({"content-type": "text/plain"}))
    check(constrainedRouteWithHeader.status == routingSuccess)
    let constrainedRouteNoHeader = r.route("GET", parseUri("/constrained"))
    check(constrainedRouteNoHeader.status == routingFailure)
    let unconstrainedRouteWithHeader = r.route("GET", parseUri("/unconstrained"), newHttpHeaders({"content-type": "text/plain"}))
    check(unconstrainedRouteWithHeader.status == routingSuccess)
    let unconstrainedRouteNoHeader = r.route("GET", parseUri("/unconstrained"))
    check(unconstrainedRouteNoHeader.status == routingSuccess)
