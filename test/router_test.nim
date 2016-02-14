import unittest, uri
import router

suite "Mappings":
  proc testHandler() = echo "test"

  test "Root":
    let r = newRouter[proc()]()
    r.map(testHandler, GET, "/")
    let result = r.route("GET", parseUri("/"))
    check(result.handler == testHandler)

  test "Duplicate root":
    let r = newRouter[proc()]()
    r.map(testHandler, GET, "/")
    let result = r.route("GET", parseUri("/"))
    check(result.handler == testHandler)
    expect MappingError:
      r.map(testHandler, GET, "/")

  test "Ends with wildcard":
    let r = newRouter[proc()]()
    r.map(testHandler, GET, "/*")
    let result = r.route("GET", parseUri("/wildcard1"))
    check(result.status == routingSuccess)
    check(result.handler == testHandler)

  test "Ends with param":
    let r = newRouter[proc()]()
    r.map(testHandler, GET, "/{param1}")
    let result = r.route("GET", parseUri("/value1"))
    check(result.status == routingSuccess)
    check(result.handler == testHandler)
    check(result.arguments.pathArgs.getOrDefault("param1") == "value1")

  test "Wildcard in middle":
    let r = newRouter[proc()]()
    r.map(testHandler, GET, "/*/test")
    let result = r.route("GET", parseUri("/wildcard1/test"))
    check(result.status == routingSuccess)
    check(result.handler == testHandler)

  test "Param in middle":
    let r = newRouter[proc()]()
    r.map(testHandler, GET, "/{param1}/test")
    let result = r.route("GET", parseUri("/value1/test"))
    check(result.status == routingSuccess)
    check(result.handler == testHandler)
    check(result.arguments.pathArgs.getOrDefault("param1") == "value1")

  test "Param + wildcard":
    let r = newRouter[proc()]()
    r.map(testHandler, GET, "/{param1}/*")
    let result = r.route("GET", parseUri("/value1/test"))
    check(result.status == routingSuccess)
    check(result.handler == testHandler)
    check(result.arguments.pathArgs.getOrDefault("param1") == "value1")

  test "Wildcard + param":
    let r = newRouter[proc()]()
    r.map(testHandler, GET, "/*/{param1}")
    let result = r.route("GET", parseUri("/somevalue/value1"))
    check(result.status == routingSuccess)
    check(result.handler == testHandler)
    check(result.arguments.pathArgs.getOrDefault("param1") == "value1")

  test "Trailing slash has no effect":
    let r = newRouter[proc()]()
    r.map(testHandler, GET, "/some/url/")
    let result1 = r.route("GET", parseUri("/some/url"))
    check(result1.status == routingSuccess)
    let result2 = r.route("GET", parseUri("/some/url/"))
    check(result2.status == routingSuccess)

  test "Trailing slash doesn't make a unique mapping":
    let r = newRouter[proc()]()
    r.map(testHandler, GET, "/some/url/")
    expect MappingError:
      r.map(testHandler, GET, "/some/url")

  test "Varying param names don't make a unique mapping":
    let r = newRouter[proc()]()
    r.map(testHandler, GET, "/has/{paramA}")
    expect MappingError:
      r.map(testHandler, GET, "/has/{paramB}")

  test "Param vs wildcard don't make a unique mapping":
    let r = newRouter[proc()]()
    r.map(testHandler, GET, "/has/{param}")
    expect MappingError:
      r.map(testHandler, GET, "/has/*")

  test "Wildcards only match one URL section":
    let r = newRouter[proc()]()
    r.map(testHandler, GET, "/has/*/one")
    let result = r.route("GET", parseUri("/has/a/b/one"))
    check(result.status == routingFailure)
