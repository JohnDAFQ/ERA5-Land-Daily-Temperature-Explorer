# ERA5-Land Global Warming Explorer (Shiny)

Enter latitude/longitude and a date range to fetch ERA5-Land daily `temperature_2m_mean`
via Open-Meteo, visualize the series, and fit a linear trend (slope & total change).

- **End date is capped** to UTC-7 days (ERA5-Land archive lag).
- Robust fetching with retries and chunking.
- Files: `global.R`, `ui.R`, `server.R` (in `Daily-Temperature-Explorer/`)

## Run locally
```r
shiny::runApp("Daily-Temperature-Explorer")

Data Sources Summary

This project uses ERA5-Land reanalysis data (via the Open-Meteo API) for hourly 2 m temperature at ~9 km resolution, available globally from 1950 to present with ~5-day latency. ERA5-Land is produced by ECMWF’s Copernicus Climate Change Service and is widely validated in peer-reviewed studies, though local biases may occur.

For finer spatial context, alternative datasets include:

MODIS LST – 1 km, twice daily (sun-synchronous, cloud-limited).

Himawari-8/9 – 2 km, every 10 minutes (tropical Asia–Pacific, excellent diurnal coverage).

ECOSTRESS (ISS) – ~70 m, irregular ~3–5 day revisit, varying local times, ideal for canopy-scale extremes.

Project’s baseline, with bias correction applied using local BoM station data to better represent orchard conditions.
