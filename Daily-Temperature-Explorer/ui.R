# tools/update_env.R
# One-command environment updater for a Shiny + renv project (Windows/OneDrive friendly)

message("▶ Starting environment update...")

# ==== SETTINGS (override via env vars if you like) ===========================
CRAN_REPO        <- Sys.getenv("CRAN_REPO",        unset = "https://cloud.r-project.org")
DO_UPDATE        <- as.logical(Sys.getenv("DO_UPDATE",        unset = "TRUE"))   # update pkgs to latest?
DO_TEST          <- as.logical(Sys.getenv("DO_TEST",          unset = "TRUE"))   # run tests/smoke checks?
DO_GIT           <- as.logical(Sys.getenv("DO_GIT",           unset = "TRUE"))   # git add/commit/push?
DO_RENV_UPGRADE  <- as.logical(Sys.getenv("DO_RENV_UPGRADE",  unset = "FALSE"))  # upgrade renv? (may restart R)
GIT_MESSAGE      <- Sys.getenv("GIT_MESSAGE",      unset = "Update deps & snapshot via updater script")
# ============================================================================

quietly <- function(expr) { suppressWarnings(suppressMessages(force(expr))) }

# --- Helpers for Windows + OneDrive performance -----------------------------
project_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
onedrive_root <- Sys.getenv("OneDrive", unset = "")
is_onedrive <- nzchar(onedrive_root) && startsWith(tolower(project_root), tolower(normalizePath(onedrive_root, winslash="/", mustWork=FALSE)))

# Write or append key=val to a project-level .Renviron
write_project_renviron_entry <- function(key, value) {
  renv_file <- file.path(project_root, ".Renviron")
  lines <- if (file.exists(renv_file)) readLines(renv_file, warn = FALSE) else character()
  key_pat <- paste0("^\\s*", gsub("([\\^\\$\\*\\+\\?\\(\\)\\[\\]\\{\\}\\|\\.])","\\\\\\1", key), "\\s*=")
  if (any(grepl(key_pat, lines))) {
    # replace existing
    lines <- sub(key_pat, paste0(key, "=", value), lines)
  } else {
    lines <- c(lines, paste0(key, "=", value))
  }
  writeLines(lines, renv_file, useBytes = TRUE)
}

# Ensure cache path off OneDrive for speed
if (is_onedrive) {
  cache_path <- Sys.getenv("RENV_PATHS_CACHE", unset = "C:/renv-cache")
  if (!dir.exists(cache_path)) {
    dir.create(cache_path, recursive = TRUE, showWarnings = FALSE)
  }
  # Persist cache location at project level to avoid slow OneDrive
  write_project_renviron_entry("RENV_PATHS_CACHE", cache_path)
  message("• OneDrive detected; using renv cache at: ", cache_path)
}

# Optional: if sandbox warnings persist and you prefer to disable sandbox for THIS project, set to TRUE
DISABLE_SANDBOX <- as.logical(Sys.getenv("DISABLE_SANDBOX", unset = "FALSE"))
if (isTRUE(DISABLE_SANDBOX)) {
  write_project_renviron_entry("RENV_CONFIG_SANDBOX_ENABLED", "FALSE")
  message("• Sandbox disabled for this project (RENV_CONFIG_SANDBOX_ENABLED=FALSE).")
}

# --- Git ignore hygiene ------------------------------------------------------
append_unique_lines <- function(path, new_lines) {
  existing <- if (file.exists(path)) readLines(path, warn = FALSE) else character()
  merged <- unique(c(existing, new_lines))
  writeLines(merged, path, useBytes = TRUE)
}
append_unique_lines(file.path(project_root, ".gitignore"),
                    c(".RData", ".Rhistory", ".Rproj.user", "rsconnect/", ".DS_Store"))

# --- Ensure renv is installed & activated -----------------------------------
if (!requireNamespace("renv", quietly = TRUE)) {
  message("• Installing renv (project bootstrap)...")
  install.packages("renv", repos = CRAN_REPO)
}

message("• Activating renv...")
quietly(renv::activate())

if (isTRUE(DO_RENV_UPGRADE)) {
  message("• Upgrading renv if needed (may restart R once)...")
  quietly(renv::upgrade())
} else {
  message("• Skipping renv upgrade (DO_RENV_UPGRADE=FALSE).")
}

# Standardise CRAN + cache
message("• Setting CRAN to: ", CRAN_REPO)
quietly(renv::settings$cran(CRAN_REPO))
quietly(renv::settings$use.cache(TRUE))

# Create initial lockfile if missing (so we can update safely)
if (!file.exists(file.path(project_root, "renv.lock"))) {
  message("• No renv.lock found; creating an initial snapshot...")
  quietly(renv::snapshot(prompt = FALSE))
}

# --- Update packages (optional) ---------------------------------------------
if (isTRUE(DO_UPDATE)) {
  message("• Updating project packages to latest...")
  tryCatch(
    quietly(renv::update()),
    error = function(e) {
      message("! renv::update() error: ", e$message)
      message("  You can re-run after resolving any build issues.")
    }
  )
} else {
  message("• Skipping package updates (DO_UPDATE=FALSE).")
}

# --- Tests / smoke checks (optional) ----------------------------------------
if (isTRUE(DO_TEST)) {
  message("• Running quick checks...")
  
  # testthat (if present)
  if (dir.exists("tests") || file.exists("tests/testthat.R")) {
    message("  - testthat")
    quietly({
      if (!requireNamespace("testthat", quietly = TRUE)) install.packages("testthat", repos = CRAN_REPO)
      testthat::test_dir("tests")
    })
  } else {
    message("  - testthat: no tests/ directory found (skipping)")
  }
  
  # shinytest2 (if package & tests present)
  if (requireNamespace("shinytest2", quietly = TRUE) && dir.exists("tests/testthat")) {
    message("  - shinytest2")
    quietly({
      shinytest2::test_app(".")
    })
  } else {
    message("  - shinytest2: package or tests not present (skipping)")
  }
  
  # very light Shiny smoke check (avoid blocking server)
  if (file.exists("app.R") || (file.exists("ui.R") && file.exists("server.R"))) {
    message("  - Shiny smoke check (loading app definition)")
    quietly({
      if (!requireNamespace("shiny", quietly = TRUE)) install.packages("shiny", repos = CRAN_REPO)
      app <- shiny::appDir("."); rm(app)
    })
  } else {
    message("  - Shiny smoke check: no app.R or ui.R+server.R (skipping)")
  }
} else {
  message("• Skipping tests/smoke checks (DO_TEST=FALSE).")
}

# --- Snapshot exact working versions ----------------------------------------
message("• Writing renv.lock snapshot...")
quietly(renv::snapshot(prompt = FALSE))

message("• renv status:")
print(renv::status())

# --- Git add/commit/push (optional) -----------------------------------------
if (isTRUE(DO_GIT)) {
  message("• Committing changes to git...")
  files <- c("renv.lock", "renv/activate.R", ".Rprofile", "DESCRIPTION", "NAMESPACE")
  files <- files[file.exists(files)]
  
  # Stage lockfile + bootstrap files
  if (length(files)) system2("git", c("add", files), stdout = TRUE, stderr = TRUE)
  # Stage any other modified files you want to keep (safe no-op if none)
  system2("git", c("add", "-A"), stdout = TRUE, stderr = TRUE)
  
  # Commit (no-op if nothing staged)
  system2("git", c("commit", "-m", shQuote(GIT_MESSAGE)), stdout = TRUE, stderr = TRUE)
  
  # Push (ignore error if no upstream yet)
  system2("git", c("push"), stdout = TRUE, stderr = TRUE)
} else {
  message("• Skipping git commit/push (DO_GIT=FALSE).")
}

message("✅ Done. All set!")
