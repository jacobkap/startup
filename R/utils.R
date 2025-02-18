stop_if_not <- function(...) {
  res <- list(...)
  n <- length(res)
  if (n == 0L) return()

  for (ii in 1L:n) {
    res_ii <- .subset2(res, ii)
    if (length(res_ii) != 1L || is.na(res_ii) || !res_ii) {
        mc <- match.call()
        call <- deparse(mc[[ii + 1]], width.cutoff = 60L)
        if (length(call) > 1L) call <- paste(call[1L], "...")
        stop(sQuote(call), " is not TRUE", call. = FALSE, domain = NA)
    }
  }
}

eof_ok <- function(file) {
  size <- file.info(file)$size
  ## On Windows, symbolic links give size = 0
  if (.Platform$OS.type == "windows" && size == 0L) size <- 1e9
  bfr <- readBin(file, what = "raw", n = size)
  n <- length(bfr)
  if (n == 0L) return(FALSE)
  is.element(bfr[n], charToRaw("\n\r"))
}

is_dir <- function(f) nzchar(f) && file.exists(f) && file.info(f)$isdir

is_file <- function(f) nzchar(f) && file.exists(f) && !file.info(f)$isdir

nlines <- function(f) {
  bfr <- readLines(f, warn = FALSE)
  bfr <- grep("^[ \t]*#", bfr, value = TRUE, invert = TRUE)
  bfr <- grep("^[ \t]*$", bfr, value = TRUE, invert = TRUE)
  length(bfr)
}

## base::file.size() was only introduced in R 3.2.0
file_size <- function(...) file.info(..., extra_cols = FALSE)$size

path_info <- function(f, extra = NULL) {
  if (!nzchar(f)) return(sQuote(""))
  fx <- path.expand(f)
  if (!is.null(extra)) {
    extra <- paste("; ", extra, sep = "")
  } else {
    extra <- ""
  }

  if (!is_dir(f)) {
    return(sprintf("%s (non-existing directory%s)", sQuote(f), extra))
  }

  if (fx == f) {
    sprintf("%s (existing folder%s)", sQuote(f), extra)
  } else {
    sprintf("%s => %s (existing folder%s)", sQuote(f), sQuote(fx), extra)
  }
}


file_info <- function(f, type = "txt", extra = NULL) {
  if (!nzchar(f)) return(sQuote(""))
  fx <- path.expand(f)
  if (length(extra) > 0L) {
    extra <- paste("; ", extra, sep = "")
  } else {
    extra <- ""
  }
  if (!is_file(f)) {
    return(sprintf("%s (non-existing file%s)", sQuote(f), extra))
  }

  if (fx == f) {
    prefix <- sQuote(f)
  } else {
    prefix <- sprintf("%s => %s", sQuote(f), sQuote(fx))
  }
  if (type == "binary") {
    sprintf("%s (binary file; %d bytes%s)", prefix, file_size(f), extra)
  } else if (type == "env") {
    vars <- names(parse_renviron(f))
    nvars <- length(vars)
    if (nvars > 0) {
      vars <- sprintf(" (%s)", paste(sQuote(vars), collapse = ", "))
    } else {
      vars <- ""
    }
    sprintf("%s (%d lines; %d bytes%s) setting %d environment variables%s",
            prefix, nlines(f), file_size(f), extra, nvars, vars)
  } else if (type == "r") {
    sprintf("%s (%d code lines; %d bytes%s)",
            prefix, nlines(f), file_size(f), extra)
  } else {
    sprintf("%s (%d lines; %d bytes%s)",
            prefix, nlines(f), file_size(f), extra)
  }
}

parse_renviron <- function(f) {
  bfr <- readLines(f, warn = FALSE)
  bfr <- grep("^[ \t]*#", bfr, value = TRUE, invert = TRUE)
  bfr <- grep("^[ \t]*$", bfr, value = TRUE, invert = TRUE)
  bfr <- grep("=.*$", bfr, value = TRUE)
  pattern <- "^(.*)[ \t]*=[ \t]*(.*)$"
  bfr <- grep(pattern, bfr, value = TRUE)
  names <- gsub(pattern, "\\1", bfr)
  values <- gsub(pattern, "\\2", bfr)
  names(values) <- names
  values
}

find <- function(what, mode) {
  paths <- search()
  for (pos in seq_along(paths)) {
    if (exists(what, mode = mode, where = pos, inherits = FALSE)) {
      return(structure(pos, names = names(paths)[pos]))
    }
  }
  -1L
}

