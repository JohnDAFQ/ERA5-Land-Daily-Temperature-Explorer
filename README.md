# ERA5-Land Global Warming Explorer (Shiny)

Enter latitude/longitude and a date range to fetch ERA5-Land daily `temperature_2m_mean`
via Open-Meteo, visualize the series, and fit a linear trend (slope & total change).

- **End date is capped** to UTC-7 days (ERA5-Land archive lag).
- Robust fetching with retries and chunking.
- Files: `global.R`, `ui.R`, `server.R` (in `Daily-Temperature-Explorer/`)

## Run locally
```r
shiny::runApp("Daily-Temperature-Explorer")
