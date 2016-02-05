proc log*(messages : varargs[string]) =
  try:
    for message in items(messages):
      write(stdout, message)
    write(stdout, "\n")
  except IOError:
    quit(QuitFailure)
