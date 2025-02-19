#' Load .Renviron.d and .Rprofile.d directories during the R startup process
#'
#' Initiates \R using all files under \file{.Renviron.d/} and / or
#' \file{.Rprofile.d/} directories (or in subdirectories thereof).
#'
#' The above is done in addition the \file{.Renviron} and \file{.Rprofile}
#' files that are supported by the built-in [startup process][base::Startup]
#' of \R.
#'
#' @param sibling If `TRUE`, then only \file{.Renviron.d/} and
#' \file{.Rprofile.d/} directories with a sibling \file{.Renviron} and
#' \file{.Rprofile} in the same location will be considered.
#'
#' @param all If `TRUE`, then _all_ \file{.Renviron.d/} and \file{.Rprofile.d/}
#' directories found on [the R startup search path][base::Startup] are
#' processed, otherwise only the _first ones_ found.
#'
#' @param on_error Action taken when an error is detected when sourcing an
#' Rprofile file.  It is not possible to detect error in Renviron files;
#' they are always ignored with a message that cannot be captured.
#'
#' @param keep Specify what information should remain after this function
#' complete.  The default is to keep `startup.session.*` options
#' as recorded by [startup_session_options()].
#'
#' @param check If `TRUE`, then the content of startup files are validated.
#' 
#' @param unload If `TRUE`, then the package is unloaded afterward, otherwise
#' not.
#'
#' @param skip If `TRUE`, startup directories will be skipped.  If `NA`, they
#' will be skipped if command-line options `--vanilla`, `--no-init-file`,
#' and / or `--no-environ` were specified.
#'
#' @param dryrun If `TRUE`, everything is done except the processing of the
#' startup files.
#'
#' @param debug If `TRUE`, debug messages are outputted, otherwise not.
#'
#' @section User-specific installation:
#' In order for \file{.Rprofile.d} and \file{.Renviron.d} directories to be
#' included during the \R startup process, a user needs to add
#' `startup::startup()` to \file{~/.Rprofile}.  Adding this can also be done
#' by calling [startup::install()] once.
#'
#' @section Site-wide installation:
#' An alternative to having each user add `startup::startup()` in their own
#' \file{~/.Rprofile} file, is to add it to the site-wide \file{Rprofile.site}
#' file (see [?Startup][base::Startup]).
#' The advantage of such a site-wide installation, is that the users do not
#' have to have a \file{.Rprofile} file for \file{.Rprofile.d} and
#' \file{.Renviron.d} directories to work.
#' For this to work for all users automatically, the \pkg{startup} package
#' should also be installed in the site-wide library.
#'
#' @examples
#' \dontrun{
#' # The most common way to use the package is to add
#' # the following call to the ~/.Rprofile file.
#' startup::startup()
#'
#' # For finer control of on exactly what files are used
#' # functions renviron_d() and rprofile_d() are also available:
#'
#' # Initiate first .Renviron.d/ found on search path
#' startup::renviron_d()
#'
#' # Initiate all .Rprofile.d/ directories found on the startup search path
#' startup::rprofile_d(all = TRUE)
#' }
#'
#' @describeIn startup `renviron_d()` followed by `rprofile_d()` and then the
#' package is unloaded
#' @export
startup <- function(sibling = FALSE, all = FALSE,
                    on_error = c("error", "warning", "immediate.warning",
                                 "message", "ignore"),
                    keep = c("options"), check = NA, unload = TRUE, skip = NA,
                    dryrun = NA, debug = NA) {
  on_error <- match.arg(on_error)
  if (length(keep) > 0) keep <- match.arg(keep, several.ok = TRUE)

  debug(debug)

  debug <- debug()
  if (debug) {
    cmd_args <- getOption("startup.debug.commandArgs", commandArgs())
    r_home <- R.home()
    r_arch <- .Platform$r_arch
    r_os <- .Platform$OS.type

    logf("System information:")
    logf("- R_HOME: %s", path_info(Sys.getenv("R_HOME")))
    logf("- R call: %s", paste(cmd_args, collapse = " "))
    logf("- Current directory: %s", sQuote(getwd()))
    logf("- User's home directory: %s", path_info("~"))
    logf("- Search path: %s", paste(sQuote(search()), collapse = ", "))
    logf("- Loaded namespaces: %s",
         paste(sQuote(loadedNamespaces()), collapse = ", "))

    logf("The following has already been processed by R:")

    logf("- R_ENVIRON: %s", file_info(Sys.getenv("R_ENVIRON"), type = "env"))
    logf("- R_ENVIRON_USER: %s", file_info(Sys.getenv("R_ENVIRON_USER"), type = "env"))
    
    if (r_os == "unix") {
      f <- file.path(r_home, "etc", "Renviron")
      if (is_file(f)) logf("- %s", file_info(f, type = "env"))
    }

    no_environ <- any(c("--no-environ", "--vanilla") %in% cmd_args)
    if (!no_environ) {
      f <- Sys.getenv("R_ENVIRON")
      if (nzchar(r_arch) && !is_file(f)) {
        f <- file.path(r_home, "etc", r_arch, "Renviron.site")
      }
      if (!is_file(f)) f <- file.path(r_home, "etc", "Renviron.site")
      if (is_file(f)) logf("- %s", file_info(f, type = "env"))

      f <- Sys.getenv("R_ENVIRON_USER")
      if (nzchar(r_arch) && !is_file(f)) f <- sprintf(".Renviron.%s", r_arch)
      if (!is_file(f)) f <- ".Renviron"
      if (nzchar(r_arch) && !is_file(f)) f <- sprintf("~/.Renviron.%s", r_arch)
      if (!is_file(f)) f <- "~/.Renviron"
      if (is_file(f)) logf("- %s", file_info(f, type = "env"))
    }

    pkgs <- Sys.getenv("R_DEFAULT_PACKAGES")
    if (pkgs == "") {
      ## In R (< 3.5.0), the 'methods' package is _not_ attached when Rscript
      ## is used.  In R (>= 3.5.0), the 'methods' package is always attached
      ## by default.  If attached, the 'methods' package is attached at the
      ## very beginning when R is started moments after the 'base' package is
      ## attached.  This is contrary to all other packages which are attached
      ## below.
      ## An good-enough test to check if running Rscript (< 3.5.0):
      if (getRversion() < "3.5.0" &&
          basename(cmd_args[1]) %in% c("Rscript", "Rscript.exe")) {
        pkgs <- "base,datasets,utils,grDevices,graphics,stats"
      } else {
        pkgs <- "base,methods,datasets,utils,grDevices,graphics,stats"
      }
      logf("- R_DEFAULT_PACKAGES: %s (= %s)", sQuote(""), sQuote(pkgs))
    } else {
      logf("- R_DEFAULT_PACKAGES: %s", sQuote(pkgs))
    }

    logf("- R_LIBS: %s", sQuote(Sys.getenv("R_LIBS")))
    logf("- R_LIBS_SITE: %s", sQuote(Sys.getenv("R_LIBS_SITE")))
    logf("- R_LIBS_USER: %s", sQuote(Sys.getenv("R_LIBS_USER")))

    logf("- R_PROFILE: %s", file_info(Sys.getenv("R_PROFILE")))
    logf("- R_PROFILE_USER: %s", file_info(Sys.getenv("R_PROFILE_USER")))
    no_site_file <- any(c("--no-site-file", "--vanilla") %in% cmd_args)
    if (!no_site_file) {
      f <- Sys.getenv("R_PROFILE")
      if (nzchar(r_arch) && !is_file(f)) {
        f <- file.path(r_home, "etc", r_arch, "Rprofile.site")
      }
      if (!is_file(f)) f <- file.path(r_home, "etc", "Rprofile.site")
      if (is_file(f)) logf("- %s", file_info(f, type = "r"))
    }

    no_init_file <- any(c("--no-init-file", "--vanilla") %in% cmd_args)
    if (!no_init_file) {
      f <- Sys.getenv("R_PROFILE_USER")
      if (nzchar(r_arch) && !is_file(f)) f <- sprintf(".Rprofile.%s", r_arch)
      if (!is_file(f)) f <- ".Rprofile"
      if (nzchar(r_arch) && !is_file(f)) f <- sprintf("~/.Rprofile.%s", r_arch)
      if (!is_file(f)) f <- "~/.Rprofile"
      if (is_file(f)) logf("- %s", file_info(f, type = "r"))
    }

    f <- Sys.getenv("R_TESTS")
    if (nzchar(f)) {
      logf(" Detected R_TESTS=%s:", sQuote(f))
      logf(" - %s%s", normalizePath(f, mustWork = FALSE),
           if (is_file(f)) "" else " (not found)")
    }
  }

  logf("startup::startup()-specific processing ...")

  # (i) Load custom .Renviron.d/* files
  renviron_d(sibling = sibling, all = all, skip = skip, dryrun = dryrun)

  # (ii) Load custom .Rprofile.d/* files
  rprofile_d(sibling = sibling, all = all, check = check, skip = skip,
             dryrun = dryrun, on_error = on_error)

  ## (iii) Process R_STARTUP_INIT code?
  code <- Sys.getenv("R_STARTUP_INIT")
  if (nzchar(code)) {
    logf("Processing R_STARTUP_INIT=%s:", sQuote(code))
    expr <- tryCatch(parse(text = code), error = identity)
    if (inherits(expr, "error")) {
      msg <- sprintf("Syntax error in 'R_STARTUP_INIT': %s", sQuote(code))
      logf(paste("- [SKIPPED]", msg))
      if (on_error == "error") {
        stop(msg, call. = FALSE)
      } else if (on_error == "warning") {
        warning(msg, call. = FALSE)
      } else if (on_error == "immediate.warning") {
        warning(msg, immediate. = TRUE, call. = FALSE)
      } else if (on_error == "message") {
        message(msg)
      }
    } else {
      eval(expr, envir = .GlobalEnv, enclos = baseenv())
    }
  }

  ## (iv) Detect and report on run-time startup issues
  check_r_libs_env_vars(debug = debug)
  check_rstudio_option_error_conflict(debug = debug)
  
  res <- api()

  ## (v) Cleanup?
  if (!"options" %in% keep) startup_session_options(action = "erase")

  ## Needed because we might unload package below and then we will
  ## lose timestamp() and logf()
  if (debug) {
    copy_fcn <- function(names, env = parent.frame()) {
      ns <- getNamespace("startup")
      for (name in names) {
        fcn <- get(name, mode = "function", envir = ns)
        environment(fcn) <- env
        assign(name, fcn, envir = env)
      }
    }
    t0 <- timestamp(get_t0 = TRUE)
    copy_fcn(c("timestamp", "is_file", "nlines", "file_info"))
    logf <- function(fmt, ...) {
      fmt <- paste(timestamp(), ": ", fmt, sep = "")
      message(sprintf(fmt, ...))
    }

  }

  # (vi) Unload package?
  if (unload) unload(debug = debug)

  if (debug) {
    logf("- Search path: %s", paste(sQuote(search()), collapse = ", "))
    logf("- Loaded namespaces: %s",
         paste(sQuote(loadedNamespaces()), collapse = ", "))

    interactive <- interactive()

    logf("startup::startup()-specific processing ... done")
    logf("The following will be processed next by R:")

    no_restore_data <- any(c("--no-restore-data", "--no-restore", "--vanilla") %in% cmd_args)
    loads_RData <- FALSE
    if (!no_restore_data) {
      if (is_file(f <- "./.RData")) {
        loads_RData <- TRUE
        logf("- %s", file_info(f, type = "binary"))
      }
    }

    logf("- R_HISTFILE: %s", sQuote(Sys.getenv("R_HISTFILE")))
    no_restore_history <- any(c("--no-restore-history", "--no-restore", "--vanilla") %in% cmd_args)
    if (!no_restore_history && interactive) {
      if (is_file(f <- Sys.getenv("R_HISTFILE", "./.Rhistory"))) {
        logf("- %s", file_info(f, type = "txt"))
      }
    }

    where <- find(".First", mode = "function")
    if (where > 0) {
      logf("- .First(): in %s (position %d on search())", sQuote(search()[where]), where)
    } else if (loads_RData) {
      logf("- .First(): no such function on search(), but it might be that one is defined in the ./RData file")
    } else {
      logf("- .First(): no such function on search()")
    }

    pkgs <- unlist(strsplit(pkgs, split = ",", fixed = TRUE))
    to_be_attached <- !is.element(paste("package:", pkgs, sep = ""), search())
    pkgs <- pkgs[to_be_attached]
    logf("- Remaining packages per R_DEFAULT_PACKAGES to be attached by base::.First.sys() (in order): %s",
         paste(sQuote(pkgs), collapse = ", "))
  }
  
  invisible(res)
}
