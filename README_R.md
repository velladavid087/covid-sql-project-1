R Visualization README

Prerequisites
- R >= 4.0
- The following R packages: DBI, RPostgres, dplyr, lubridate, ggplot2, scales, zoo, tidyr

Install packages in R:

install.packages(c('DBI','RPostgres','dplyr','lubridate','ggplot2','scales','zoo','tidyr'))

Run the scripts
From the repository root run either:

Rscript r_scripts/visualize_trends.R

or

Rscript r_scripts/epi_visualize.R

or

Rscript r_scripts/visualize_epi_table.R

This script runs a single SQL query (defined inside the script) that produces a comprehensive epidemiology table by joining `worldometer_data` and `country_wise_latest`. It then creates plots in `r_scripts/plots/epi_table` and saves `epi_table.csv` for inspection.

If you want to customize the SQL, edit `r_scripts/visualize_epi_table.R` and change the `sql` variable at the top.

Outputs
- `r_scripts/plots/new_cases_7d_top6.png` - 7-day average new cases plot for top 6 countries by confirmed cases
- `r_scripts/plots/cfr_top20.png` - Top 20 CFR bar chart
- `r_scripts/plots/incidence_per_100k_top20.png` - New cases per 100k (snapshot)
- `r_scripts/plots/deaths_per_100k_top20.png` - Deaths per 100k (cumulative)
- `r_scripts/plots/wm_vs_cwl_scatter.png` - worldometer vs country_wise_latest scatter
- `r_scripts/plots/summary_metrics.csv` - summary CSV with latest metrics

Notes
- The scripts attempt to discover common column names (e.g., `observation_date` or `date`) — if your `covid_data` table uses different names, update the SQL query at the top of the script.
- If your postgres user requires a password or different connection settings, set the environment variables or edit the `dbConnect` call in the script.

Quick VS Code setup to use your user R library
- A helper file `.Renviron.user` has been created in the repo root. To make R use your `~/Rlib` automatically, move it into your home directory:

```bash
mv .Renviron.user ~/.Renviron
```

- After placing `~/.Renviron`, restart VS Code (or reload the window) so the R extension spawns an R process that sees `R_LIBS_USER=~/Rlib`.
- If VS Code still uses a different R binary (for example a conda R), open settings and set `r.rterm.linux` to the full path of the `R` you used in the terminal (find it with `which R`).
