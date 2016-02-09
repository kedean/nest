# Nest
RESTful routing with Nim!

## Intro
Nest is a high performance URL mapper/router built in Nim.

At the moment, Nest needs a lot of work and is *definitely* not ready for production. Feedback is appreciated!

## Usage
See examples/ for example usage. Note that using this against Nim's built in asynchttpserver is not required, and it is just used for the examples.

## Compilation
To run the example code, use the following invocation:
```nim
nim c --path:./ --threads:on -r examples/example1.nim
```
Threads do not need to be enabled, this just shows that they can be.

## Features
- Map against any HTTP method and path
- Server-agnostic
- URL parameter capture
- Query string/body parameter capture
- Plays nice with various logging systems
- Does not impose restrictions on your handler methods

## Future Features
- Benchmarking against other routers
- Adding consumes/produces constraints
- Removing dependency on HTTP, allow routing on other transport protocols
- Improve body parameter capture (JSON support?)
- More documentation!
- Guarantee thread safety
- Performance improvements
