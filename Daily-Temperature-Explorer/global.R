# ============================================================
# Global: packages, helpers, data fetcher (shared by ui/server)
# ============================================================

need <- c("shiny","bslib","dplyr", "ggplot2", "lubridate","scales","readr", "httr2")

to_install <- need[!need %in% rownames(installed.packages())]

if (length(to_install)) install.packages(to_install, repos = "https://cloud.r-project.org")
invisible(lapply(need, library, character.only = TRUE))

# Latest date ERA5-Land archive is safely available for (≈7-day lag)
era5_latest_date <- function() {
  as.Date(lubridate::with_tz(Sys.time(), "UTC")) - 7
}


# Simple value box using bslib cards
value_box <- function(title, value, subtitle = NULL) {
  bslib::card(
    class = "mb-3",
    bslib::card_header(title),
    bslib::card_body(
      tags$div(style = "font-size: 1.8rem; font-weight: 700;", value),
      if (!is.null(subtitle)) tags$div(style = "color:#6c757d;", subtitle)
    )
  )
}

# ERA5-Land daily mean fetcher — robust to streaming glitches & API lag
fetch_era5_daily <- function(lat, lon, start_date, end_date, chunk_years = 3) {
  start_date <- as.Date(start_date)
  end_date   <- as.Date(end_date)
  
  # Archive bounds (safe)
  archive_min    <- as.Date("1950-01-01")
  archive_latest <- as.Date(lubridate::with_tz(Sys.time(), "UTC")) - 7
  
  # Clamp
  start_date <- max(start_date, archive_min, na.rm = TRUE)
  end_date   <- min(end_date,   archive_latest, na.rm = TRUE)
  if (is.na(start_date) || is.na(end_date) || start_date > end_date) {
    stop("Invalid date range after clamping to archive availability. Try an earlier end date.")
  }
  
  # Build outer chunks
  y_start <- lubridate::year(start_date)
  y_end   <- lubridate::year(end_date)
  cut_years <- seq(y_start, y_end, by = chunk_years)
  bounds <- tibble::tibble(
    start = pmax(as.Date(sprintf("%d-01-01", cut_years)), start_date),
    end   = pmin(as.Date(sprintf("%d-12-31", pmin(cut_years + chunk_years - 1, y_end))), end_date)
  )
  
  # Safe single-range fetch with recursive split on parse errors
  fetch_range_safe <- function(s, e, depth = 0) {
    base <- "https://archive-api.open-meteo.com/v1/era5"
    req <- httr2::request(base) |>
      httr2::req_url_query(
        latitude   = lat,
        longitude  = lon,
        start_date = as.character(s),
        end_date   = as.character(e),
        daily      = "temperature_2m_mean",
        timezone   = "Australia/Brisbane",   # or "auto"/"UTC" if you prefer
        temperature_unit = "celsius"
      ) |>
      httr2::req_headers(`Accept-Encoding` = "identity", `User-Agent` = "R httr2 / ERA5-Land app") |>
      httr2::req_retry(max_tries = 5, backoff = ~ runif(1, 0.5, 1.5)) |>
      httr2::req_options(timeout = 60)
    
    resp <- try(httr2::req_perform(req), silent = TRUE)
    if (inherits(resp, "try-error")) {
      # If the chunk is large, split and try again; else return empty
      if (depth < 2 && as.numeric(e - s) > 30) {
        mid <- s + floor(as.numeric(e - s) / 2)
        return(dplyr::bind_rows(
          fetch_range_safe(s, mid, depth + 1),
          fetch_range_safe(mid + 1, e, depth + 1)
        ))
      } else {
        return(tibble::tibble(date = as.Date(character()), tmean = numeric()))
      }
    }
    
    if (httr2::resp_status(resp) >= 400) {
      return(tibble::tibble(date = as.Date(character()), tmean = numeric()))
    }
    
    # Parse as string first; confirm it's JSON
    body <- try(httr2::resp_body_string(resp), silent = TRUE)
    if (inherits(body, "try-error") || is.na(body) || !jsonlite::validate(body)) {
      if (depth < 2 && as.numeric(e - s) > 30) {
        mid <- s + floor(as.numeric(e - s) / 2)
        return(dplyr::bind_rows(
          fetch_range_safe(s, mid, depth + 1),
          fetch_range_safe(mid + 1, e, depth + 1)
        ))
      } else {
        return(tibble::tibble(date = as.Date(character()), tmean = numeric()))
      }
    }
    
    js <- jsonlite::fromJSON(body, simplifyVector = TRUE)
    if (is.null(js$daily) || is.null(js$daily$time)) {
      return(tibble::tibble(date = as.Date(character()), tmean = numeric()))
    }
    
    tibble::tibble(
      date  = as.Date(js$daily$time),
      tmean = as.numeric(js$daily$temperature_2m_mean)
    )
  }
  
  purrr::map2_dfr(bounds$start, bounds$end, fetch_range_safe) |>
    dplyr::arrange(date) |>
    dplyr::distinct(date, .keep_all = TRUE)
}
