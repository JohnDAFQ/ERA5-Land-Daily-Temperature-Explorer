# ============================================================
# Server
# ============================================================

library(shiny)
library(dplyr)
library(ggplot2)
library(lubridate)
library(scales)
library(readr)

server <- function(input, output, session) {
  
  # On session start, cap the End date to latest ERA5 day (UTC - 7d) and clamp value
  observeEvent(TRUE, {
    latest <- era5_latest_date()
    updateDateInput(session, "end", max = latest,
                    value = min(as.Date(input$end %||% latest), latest)
    )
    # also cap Start picker max to the same latest
    updateDateInput(session, "start", max = latest)
  }, once = TRUE)
  
  # If user types a too-new end date, clamp it immediately
  observeEvent(input$end, {
    latest <- era5_latest_date()
    if (!is.null(input$end) && as.Date(input$end) > latest) {
      updateDateInput(session, "end", value = latest)
    }
  }, ignoreInit = TRUE)
  
  data_r <- reactiveVal(NULL)
  
  observeEvent(input$go, {
    req(!is.null(input$lat), !is.null(input$lon), !is.null(input$start), !is.null(input$end))
    
    # Validate numeric inputs
    shiny::validate(
      shiny::need(is.finite(input$lat) && abs(input$lat) <= 90,  "Latitude must be between -90 and 90."),
      shiny::need(is.finite(input$lon) && abs(input$lon) <= 180, "Longitude must be between -180 and 180.")
    )
    
    # Enforce ERA5 archive window (latest = UTC - 7d)
    latest <- era5_latest_date()
    shiny::validate(
      shiny::need(as.Date(input$start) <= as.Date(input$end), "Start date must be on/before end date."),
      shiny::need(as.Date(input$end) <= latest,
                  paste0("End date must be \u2264 ", format(latest), " (ERA5-Land lags ~7 days)."))
    )
    
    # Clamp the range we actually request (also clamped inside fetcher)
    start_in <- max(as.Date(input$start), as.Date("1950-01-01"))
    end_in   <- min(as.Date(input$end), latest)
    
    withProgress(message = "Fetching ERA5-Land daily means…", value = 0, {
      incProgress(0.1)
      # smaller chunks are more robust; function can retry internally
      df <- fetch_era5_daily(input$lat, input$lon, start_in, end_in, chunk_years = 3)
      incProgress(0.8)
      
      df <- df %>%
        filter(!is.na(tmean)) %>%
        mutate(year_dec = decimal_date(date))
      
      shiny::validate(shiny::need(nrow(df) > 5, "No data returned for that period. Try a longer range."))
      
      data_r(df)
      incProgress(0.1)
    })
  }, ignoreInit = TRUE)
  
  slope_vals <- reactive({
    df <- req(data_r())
    fit <- lm(tmean ~ year_dec, data = df)
    slope_per_year <- unname(coef(fit)[["year_dec"]])
    span_years <- max(df$year_dec) - min(df$year_dec)
    change_model <- slope_per_year * span_years
    
    span <- as.numeric(difftime(max(df$date), min(df$date), units = "days")) / 365.25
    w <- ifelse(span >= 10, 5, max(1, floor(span / 4)))
    
    early_cut <- (min(df$date) %m+% years(w))
    late_cut  <- (max(df$date) %m-% years(w))
    
    early_mean <- df %>% filter(date <= early_cut) %>%
      summarise(m = mean(tmean, na.rm = TRUE), .groups = "drop") %>% pull(m)
    
    late_mean <- df %>% filter(date >= late_cut) %>%
      summarise(m = mean(tmean, na.rm = TRUE), .groups = "drop") %>% pull(m)
    
    list(
      slope_per_year = slope_per_year,
      slope_per_dec  = slope_per_year * 10,
      change_model   = change_model,
      early_mean     = early_mean,
      late_mean      = late_mean,
      delta_means    = late_mean - early_mean,
      span_years     = span
    )
  })
  
  output$slope_txt <- renderText({
    v <- req(slope_vals())
    sprintf("%.3f °C/decade (%.4f °C/yr)", v$slope_per_dec, v$slope_per_year)
  })
  
  output$change_txt <- renderText({
    v <- req(slope_vals())
    sprintf("%.2f °C across %.1f years", v$change_model, v$span_years)
  })
  
  output$means_txt <- renderText({
    v <- req(slope_vals())
    sprintf("%.2f \u2192 %.2f °C (\u0394 = %.2f °C)", v$early_mean, v$late_mean, v$delta_means)
  })
  
  output$meta_txt <- renderText({
    df <- req(data_r())
    rng <- sprintf("%s to %s", format(min(df$date)), format(max(df$date)))
    latest <- era5_latest_date()
    sprintf("Lat: %.5f, Lon: %.5f • %s • %d days • ERA5 available through %s (UTC)",
            input$lat, input$lon, rng, nrow(df), format(latest))
  })
  
  output$plot <- renderPlot({
    df <- req(data_r())
    
    p <- ggplot(df, aes(date, tmean)) +
      geom_line(alpha = 0.55) +
      geom_smooth(method = "lm", se = FALSE, linewidth = 1) +
      labs(
        x = NULL,
        y = "Daily mean 2 m air temperature (°C)",
        title = "Daily Temperature and Linear Trend",
        subtitle = "ERA5-Land (Open-Meteo): temperature_2m_mean"
      ) +
      scale_x_date(labels = label_date_short()) +
      theme_minimal(base_size = 13)
    
    if (isTRUE(input$annual)) {
      annual <- df %>%
        mutate(year = year(date)) %>%
        group_by(year) %>%
        summarise(tmean = mean(tmean, na.rm = TRUE), .groups = "drop") %>%
        mutate(date = as.Date(sprintf("%d-07-01", year)))
      p <- p + geom_line(data = annual, aes(date, tmean), linewidth = 1)
    }
    
    p
  })
  
  output$dl_csv <- downloadHandler(
    filename = function() {
      sprintf("era5_daily_mean_%.5f_%.5f_%s_%s.csv",
              input$lat, input$lon, input$start, input$end)
    },
    content = function(file) {
      df <- req(data_r())
      readr::write_csv(dplyr::select(df, date, temperature_2m_mean = tmean), file)
    }
  )
}
