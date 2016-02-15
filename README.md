[![Build Status](https://travis-ci.org/kedean/nest.svg?branch=master)](https://travis-ci.org/kedean/nest)

# Nest
RESTful routing with Nim!

## Intro
Nest is a high performance URL mapper/router built in Nim.

At the moment, Nest needs a work and is not ready for production. Feedback is appreciated moving forward!

## Usage
See examples/ for example usage. Note that using this against Nim's built in asynchttpserver is not required, and it is just used for the examples.

## Compilation
To run the example code, use the following invocation:
```nim
nim c -r examples/example1.nim
```
Threads are not required for nest to run, but the examples use threads (in nim.cfg) to prove that they can be used.

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
