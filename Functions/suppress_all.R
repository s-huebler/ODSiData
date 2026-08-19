suppress_all <- function(expr) {
  # invisible() prevents returning the captured output to the console
  # capture.output() grabs standard print() output
  # suppressWarnings() grabs warning()
  # suppressMessages() grabs message()
  
  invisible(
    capture.output(
      suppressWarnings(
        suppressMessages(
          result <- expr
        )
      ), 
      file = tempfile() # Sends captured standard output to a temporary trash file
    )
  )
  return(result)
}
