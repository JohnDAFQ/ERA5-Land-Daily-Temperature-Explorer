
# ============================================================
# UI
# ============================================================

library(shiny)
library(bslib)

# Uses helper defined in global.R
# era5_latest_date() -> returns Sys.time() (UTC) - 7 days
end_max <- era5_latest_date()

ui <- bslib::page_fillable(
  theme = bslib::bs_theme(version = 5, bootswatch = "flatly"),
  bslib::card(
    bslib::card_header("Global Warming Explorer — ERA5-Land (Open-Meteo)"),
    bslib::card_body(
      bslib::layout_columns(
        col_widths = c(4, 8),
        
        # Controls
        bslib::card(
          bslib::card_header("Inputs"),
          fluidRow(
            column(6, numericInput("lat", "Latitude",  value = -16.9186, step = 0.00001)),
            column(6, numericInput("lon", "Longitude", value = 145.7781,  step = 0.00001))
          ),
          fluidRow(
            column(
              6,
              dateInput(
                "start", "Start date",
                value = as.Date("1960-01-01"),
                min   = as.Date("1950-01-01"),
                max   = end_max
              )
            ),
            column(
              6,
              dateInput(
                "end", "End date",
                value = end_max,
                max   = end_max
              )
            )
          ),
          checkboxInput("annual", "Show annual mean overlay", value = TRUE),
          actionButton("go", "Get Data", class = "btn btn-primary"),
          helpText(
            paste0(
              "Data: ERA5-Land via Open-Meteo (daily temperature_2m_mean, °C). ",
              "Archive currently available through ", format(end_max), " (UTC, ≈7-day lag)."
            )
          )
        ),
        
        # Results
        bslib::card(
          bslib::card_header("Results"),
          fluidRow(
            column(4, value_box("Slope", textOutput("slope_txt"), "Linear trend")),
            column(4, value_box("Change over span", textOutput("change_txt"), "Model-implied ΔT")),
            column(4, value_box("Early vs late means", textOutput("means_txt"), "Last vs first window"))
          ),
          bslib::card_body(
            plotOutput("plot", height = "480px")
          ),
          bslib::card_footer(
            downloadButton("dl_csv", "Download CSV"),
            span(style = "margin-left:10px;color:#6c757d;",
                 textOutput("meta_txt", inline = TRUE))
          )
        )
      )
    )
  )
)
