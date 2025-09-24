# Visualize epidemiology stats from a single SQL query (table-only)
# Usage: Rscript r_scripts/visualize_epi_table.R
# Requires: DBI, RPostgres, dplyr, ggplot2, scales

library(DBI)
library(RPostgres)
library(dplyr)
library(ggplot2)
library(scales)

# Connection (override via env vars)
db_name <- Sys.getenv('COVID_DB', 'covid')
db_user <- Sys.getenv('COVID_DB_USER', 'vella87')
db_host <- Sys.getenv('COVID_DB_HOST', '')
db_port <- Sys.getenv('COVID_DB_PORT', '')
con <- dbConnect(RPostgres::Postgres(), dbname = db_name, user = db_user)

# Single SQL query that produces an epidemiology stats table
sql <- "WITH combined AS (
  SELECT
    COALESCE(wm.country_region, cwl.country_region) AS country_region,
    COALESCE(wm.population, NULL) AS population,
    COALESCE(cwl.confirmed, wm.total_cases) AS confirmed,
    COALESCE(cwl.deaths, wm.total_deaths) AS deaths,
    COALESCE(cwl.recovered, wm.total_recovered) AS recovered,
    COALESCE(wm.new_cases, cwl.new_cases) AS new_cases,
    COALESCE(wm.total_tests, NULL) AS total_tests,
    COALESCE(wm.continent, cwl.who_region) AS continent
  FROM worldometer_data wm
  FULL OUTER JOIN country_wise_latest cwl
    ON wm.country_region = cwl.country_region
)
SELECT
  country_region,
  population,
  confirmed::bigint AS confirmed,
  deaths::bigint AS deaths,
  recovered::bigint AS recovered,
  new_cases::bigint AS new_cases,
  total_tests::bigint AS total_tests,
  continent,
  CASE WHEN population IS NOT NULL AND population > 0 AND (COALESCE(new_cases,0) >= 0)
       THEN ROUND((new_cases::numeric / population) * 100000, 2) ELSE NULL END AS new_cases_per_100k,
  CASE WHEN population IS NOT NULL AND population > 0 AND (COALESCE(deaths,0) >= 0)
       THEN ROUND((deaths::numeric / population) * 100000, 2) ELSE NULL END AS deaths_per_100k,
  CASE WHEN confirmed IS NOT NULL AND confirmed > 0
       THEN ROUND((deaths::numeric / confirmed) * 100, 2) ELSE NULL END AS cfr_pct,
  CASE WHEN confirmed IS NOT NULL AND confirmed > 0
       THEN ROUND((recovered::numeric / confirmed) * 100, 2) ELSE NULL END AS recovery_pct,
  CASE WHEN population IS NOT NULL AND population > 0 AND total_tests IS NOT NULL
       THEN ROUND((total_tests::numeric / population) * 100000, 2) ELSE NULL END AS tests_per_100k
FROM combined
ORDER BY confirmed DESC NULLS LAST;"

# Execute query
cat('Running SQL and fetching epidemiology table...\n')
epi_tbl <- dbGetQuery(con, sql)
cat('Rows fetched:', nrow(epi_tbl), '\n')

# Basic cleaning
epi_tbl <- epi_tbl %>%
  mutate(
    country_region = as.character(country_region),
    population = as.numeric(population),
    confirmed = as.numeric(confirmed),
    deaths = as.numeric(deaths),
    recovered = as.numeric(recovered),
    new_cases = as.numeric(new_cases)
  )

# Create output directory
outdir <- 'r_scripts/plots/epi_table'
if(!dir.exists(outdir)) dir.create(outdir, recursive = TRUE)

# Plot: CFR top 20
p_cfr <- epi_tbl %>% filter(!is.na(cfr_pct)) %>% arrange(desc(cfr_pct)) %>% slice_head(n = 20) %>%
  ggplot(aes(x = reorder(country_region, cfr_pct), y = cfr_pct)) +
  geom_col(fill = '#D7261E') + coord_flip() +
  labs(title = 'Top 20 Case Fatality Rate (CFR)', y = 'CFR (%)', x = '') +
  theme_minimal()

ggsave(file.path(outdir, 'cfr_top20.png'), p_cfr, width = 9, height = 7)

# Plot: new cases per 100k (top 20)
p_inc <- epi_tbl %>% filter(!is.na(new_cases_per_100k)) %>% arrange(desc(new_cases_per_100k)) %>% slice_head(n = 20) %>%
  ggplot(aes(x = reorder(country_region, new_cases_per_100k), y = new_cases_per_100k)) +
  geom_col(fill = '#1F78B4') + coord_flip() + labs(title = 'New cases per 100k (latest)', y = 'New cases per 100k', x = '') + theme_minimal()

ggsave(file.path(outdir, 'new_cases_per_100k_top20.png'), p_inc, width = 9, height = 7)

# Plot: deaths per 100k (top 20)
p_deaths <- epi_tbl %>% filter(!is.na(deaths_per_100k)) %>% arrange(desc(deaths_per_100k)) %>% slice_head(n = 20) %>%
  ggplot(aes(x = reorder(country_region, deaths_per_100k), y = deaths_per_100k)) +
  geom_col(fill = '#6A4C93') + coord_flip() + labs(title = 'Deaths per 100k (cumulative)', y = 'Deaths per 100k', x = '') + theme_minimal()

ggsave(file.path(outdir, 'deaths_per_100k_top20.png'), p_deaths, width = 9, height = 7)

# Scatter: tests_per_100k vs positivity proxy (if new_cases and total_tests present)
if('tests_per_100k' %in% names(epi_tbl) & 'new_cases' %in% names(epi_tbl) & any(!is.na(epi_tbl$tests_per_100k))){
  epi_tbl <- epi_tbl %>% mutate(positivity_proxy = ifelse(!is.na(tests_per_100k) & !is.na(new_cases) & !is.na(population) & population>0, (new_cases / (tests_per_100k * population / 100000)) * 100, NA_real_))
  if(any(!is.na(epi_tbl$positivity_proxy))){
    p_pos <- epi_tbl %>% filter(!is.na(positivity_proxy) & !is.na(tests_per_100k)) %>%
      ggplot(aes(x = tests_per_100k, y = positivity_proxy)) + geom_point(alpha = 0.6) +
      labs(title = 'Positivity proxy vs tests per 100k', x = 'Tests per 100k', y = 'Positivity proxy (%)') + theme_minimal()
    ggsave(file.path(outdir, 'positivity_vs_tests.png'), p_pos, width = 8, height = 6)
  }
}

# Save the SQL table to CSV for inspection
write.csv(epi_tbl, file.path(outdir, 'epi_table.csv'), row.names = FALSE)
cat('Plots and CSV written to', outdir, '\n')

# Disconnect
dbDisconnect(con)
