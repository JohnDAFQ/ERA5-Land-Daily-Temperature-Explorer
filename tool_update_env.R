# tools/update_env.R  (v3)
# Simple, robust renv updater for Windows / OneDrive

message("▶ Starting environment update...")

CRAN_REPO       <- Sys.getenv("CRAN_REPO",       unset = "https://cloud.r-project.org")
DO_UPDATE       <- as.logical(Sys.getenv("DO_UPDATE",       unset = "TRUE"))
DO_TEST         <- as.logical(Sys.getenv("DO_TEST",         unset = "TRUE"))
DO_GIT          <- as.logical(Sys.getenv("DO_GIT",          unset = "TRUE"))
DO_RENV_UPGRADE <- as.logical(Sys.getenv("DO_RENV_UPGRADE", unset = "FALSE"))
DISABLE_SANDBOX <- as.logical(Sys.getenv("DISABLE_SANDBOX", unset = "FALSE"))
GIT_MESSAGE     <- Sys.getenv("GIT_MESSAGE",     unset = "Update deps & snapshot via updater script")

# -------- OneDrive cache hygiene (no auto-duplication) -----------------------
project_root  <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
onedrive_root <- Sys.getenv("OneDrive", unset = "")
is_onedrive   <- nzchar(onedrive_root) &&
  startsWith(tolower(project_root), tolower(normalizePath(onedrive_root, winslash="/", mustWork=FALSE)))

# Respect existing env; only set if not already set in this session
if (is_onedrive && identical(Sys.getenv("RENV_PATHS_CACHE", unset = ""), "")) {
  Sys.setenv(RENV_PATHS_CACHE = "C:/renv-cache")
}
if (!dir.exists(Sys.getenv("RENV_PATHS_CACHE", unset = ""))) {
  dir.create(Sys.getenv("RENV_PATHS_CACHE", unset = ""), recursive = TRUE, showWarnings = FALSE)
}

if (isTRUE(DISABLE_SANDBOX)) {
  Sys.setenv(RENV_CONFIG_SANDBOX_ENABLED = "FALSE")
}

# -------- Ensure renv installed / activated ----------------------------------
if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv", repos = CRAN_REPO)
}

message("• Activating renv...")
renv::activate()

if (isTRUE(DO_RENV_UPGRADE)) {
  message("• Upgrading renv (may restart once)...")
  renv::upgrade()
} else {
  message("• Skipping renv upgrade (DO_RENV_UPGRADE=FALSE).")
}

# -------- Stable repo config (works across renv versions) --------------------
message("• Setting repositories to: ", CRAN_REPO)
options(repos = c(CRAN = CRAN_REPO))
# Try renv setting if available (no error if not supported)
if ("repositories" %in% names(as.list(renv::settings))) {
  try(renv::settings$repositories(c(CRAN = CRAN_REPO)), silent = TRUE)
}

# Speedup
try(renv::settings$use.cache(TRUE), silent = TRUE)

# -------- Ensure lockfile exists before updates ------------------------------
if (!file.exists(file.path(project_root, "renv.lock"))) {
  message("• No renv.lock; creating initial snapshot...")
  renv::snapshot(prompt = FALSE)
}

# -------- Update packages ----------------------------------------------------
if (isTRUE(DO_UPDATE)) {
  message("• Updating project packages...")
  tryCatch(renv::update(),
           error = function(e) message("! renv::update() error: ", e$message))
} else {
  message("• Skipping package updates (DO_UPDATE=FALSE).")
}

# -------- Quick checks -------------------------------------------------------
if (isTRUE(DO_TEST)) {
  message("• Running quick checks...")
  if (dir.exists("tests") || file.exists("tests/testthat.R")) {
    if (!requireNamespace("testthat", quietly = TRUE))
      install.packages("testthat", repos = CRAN_REPO)
    try(testthat::test_dir("tests"), silent = TRUE)
  }
  if (file.exists("app.R") || (file.exists("ui.R") && file.exists("server.R"))) {
    if (!requireNamespace("shiny", quietly = TRUE))
      install.packages("shiny", repos = CRAN_REPO)
    invisible(try({
      app <- shiny::appDir("."); rm(app)
    }, silent = TRUE))
  }
}

# -------- Snapshot & status --------------------------------------------------
message("• Snapshotting renv.lock...")
renv::snapshot(prompt = FALSE)

message("• renv status:")
print(renv::status())

# -------- Git add/commit/push ------------------------------------------------
if (isTRUE(DO_GIT)) {
  message("• Committing changes...")
  files <- c("renv.lock", "renv/activate.R", ".Rprofile", "DESCRIPTION", "NAMESPACE")
  files <- files[file.exists(files)]
  if (length(files)) system2("git", c("add", files))
  system2("git", c("add", "-A"))
  system2("git", c("commit", "-m", shQuote(GIT_MESSAGE)))
  system2("git", c("push"))
} else {
  message("• Skipping git commit/push (DO_GIT=FALSE).")
}

message("✅ Done.")
