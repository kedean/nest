import unittest, uri
import nest

suite "Header Mapping":
  proc testHandler() = echo "test"

  test "Root with content-type header":
    let r = newRouter[proc()]()
    r.map(testHandler, $GET, "/", newStringTable("content-type", "text/plain", modeCaseInsensitive))
    let goodResult = r.route("GET", parseUri("/"), newStringTable("content-type", "text/plain", modeCaseInsensitive))
    check(goodResult.status == routingSuccess)
    let badResult = r.route("GET", parseUri("/"), newStringTable("content-type", "text/html", modeCaseInsensitive))
    check(badResult.status == routingFailure)

  test "Parameterized with content-type header":
    let r = newRouter[proc()]()
    r.map(testHandler, $GET, "/test/{param1}", newStringTable("content-type", "text/plain", modeCaseInsensitive))
    let goodResult = r.route("GET", parseUri("/test/foo"), newStringTable("content-type", "text/plain", modeCaseInsensitive))
    check(goodResult.status == routingSuccess)
    let badResult = r.route("GET", parseUri("/test/foo"), newStringTable("content-type", "text/html", modeCaseInsensitive))
    check(badResult.status == routingFailure)

  test "Root with multiple header constraints":
    let r = newRouter[proc()]()
    r.map(
      testHandler,
      $GET,
      "/",
      newStringTable(
        "host",
        "localhost",
        "content-type",
        "text/plain",
        modeCaseInsensitive
      )
    )
    let goodResult = r.route("GET", parseUri("/"), newStringTable("content-type", "text/plain", "host", "localhost", modeCaseInsensitive))
    check(goodResult.status == routingSuccess)
    let wrongContentType = r.route("GET", parseUri("/"), newStringTable("content-type", "text/html", "host", "localhost", modeCaseInsensitive))
    check(wrongContentType.status == routingFailure)
    let wrongHost = r.route("GET", parseUri("/"), newStringTable("content-type", "text/plain", "host", "127.0.0.1", modeCaseInsensitive))
    check(wrongHost.status == routingFailure)

  test "Header constraints don't conflict with other mappings":
    let r = newRouter[proc()]()
    r.map(testHandler, $GET, "/constrained", newStringTable("content-type", "text/plain", modeCaseInsensitive))
    r.map(testHandler, $GET, "/unconstrained")

    let constrainedRouteWithHeader = r.route("GET", parseUri("/constrained"), newStringTable("content-type", "text/plain", modeCaseInsensitive))
    check(constrainedRouteWithHeader.status == routingSuccess)
    let constrainedRouteNoHeader = r.route("GET", parseUri("/constrained"))
    check(constrainedRouteNoHeader.status == routingFailure)
    let unconstrainedRouteWithHeader = r.route("GET", parseUri("/unconstrained"), newStringTable("content-type", "text/plain", modeCaseInsensitive))
    check(unconstrainedRouteWithHeader.status == routingSuccess)
    let unconstrainedRouteNoHeader = r.route("GET", parseUri("/unconstrained"))
    check(unconstrainedRouteNoHeader.status == routingSuccess)
