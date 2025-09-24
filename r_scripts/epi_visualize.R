# Epidemiology statistics visualizations
# Pull data from local Postgres `covid` database and create summary metrics + plots
# Required packages: DBI, RPostgres, dplyr, lubridate, ggplot2, scales, zoo, tidyr

library(DBI)
library(RPostgres)
library(dplyr)
library(lubridate)
library(ggplot2)
library(scales)
library(zoo)
library(tidyr)

# DB connection: override via env vars if needed
db_name <- Sys.getenv('COVID_DB', 'covid')
db_user <- Sys.getenv('COVID_DB_USER', 'vella87')
db_host <- Sys.getenv('COVID_DB_HOST', '') # empty -> local
db_port <- Sys.getenv('COVID_DB_PORT', '')

con <- dbConnect(RPostgres::Postgres(), dbname = db_name, user = db_user)

# Helper: robust column selection using COALESCE for common variants
q_world <- "SELECT * FROM worldometer_data"

q_cwl <- "SELECT * FROM country_wise_latest"

# Time series (covid_data) - try to pick common names
q_ts <- "SELECT * FROM covid_data"

# Pull datasets
world <- dbGetQuery(con, q_world)
cwl <- dbGetQuery(con, q_cwl)
ts <- dbGetQuery(con, q_ts)

# Normalize column names to lowercase/safe names for discovery
clean_names <- function(df){ names(df) <- tolower(gsub('\\s+|/|\\.', '_', names(df))); df }
world <- clean_names(world)
cwl <- clean_names(cwl)
ts <- clean_names(ts)

# Helper to pick the first existing column from candidates
pick_col <- function(df, ...) {
  for (nm in c(...)) if (nm %in% names(df)) return(df[[nm]])
  return(rep(NA, nrow(df)))
}

# Rebuild tidy data.frames with canonical column names (safe if some columns are missing)
world <- tibble::tibble(
  country_region = as.character(pick_col(world, 'country_region','country','countryregion','country_name')),
  population = as.numeric(pick_col(world, 'population','population_size')),
  total_cases = as.numeric(pick_col(world, 'total_cases','totalcases','confirmed')),
  new_cases = as.numeric(pick_col(world, 'new_cases','newcases')),
  total_deaths = as.numeric(pick_col(world, 'total_deaths','totaldeaths','deaths')),
  total_recovered = as.numeric(pick_col(world, 'total_recovered','totalrecovered','recovered')),
  total_tests = as.numeric(pick_col(world, 'total_tests','totaltests','tests')),
  serious_critical = as.numeric(pick_col(world, 'serious_critical','seriouscritical')),
  continent = pick_col(world, 'continent')
)

cwl <- tibble::tibble(
  country_region = as.character(pick_col(cwl, 'country_region','country','country_name','countryregion')),
  confirmed = as.numeric(pick_col(cwl, 'confirmed','confirmed_final','confirmed_cases','total_cases')),
  deaths = as.numeric(pick_col(cwl, 'deaths','deaths')),
  recovered = as.numeric(pick_col(cwl, 'recovered','recovered')),
  active = as.numeric(pick_col(cwl, 'active','active_cases')),
  new_cases = as.numeric(pick_col(cwl, 'new_cases','new_cases_cwl','newcases','new_cases')),
  new_deaths = as.numeric(pick_col(cwl, 'new_deaths','new_deaths','newdeaths')),
  deaths_per_100_cases = pick_col(cwl, 'deaths_per_100_cases','deaths_per_100_recovered'),
  who_region = pick_col(cwl, 'who_region','who_region')
)

# TS cleanup and canonicalization
ts <- ts %>% mutate(
  obs_date = as.Date(pick_col(ts, 'obs_date','observation_date','date','dt')),
  country_region = as.character(pick_col(ts, 'country_region','country','country_name')),
  province_state = as.character(pick_col(ts, 'province_state','province','state')),
  confirmed = as.numeric(pick_col(ts, 'confirmed','total_cases','confirmed_cases')),
  deaths = as.numeric(pick_col(ts, 'deaths','total_deaths')),
  new_cases = as.numeric(pick_col(ts, 'new_cases','newcases'))
) %>% arrange(country_region, obs_date)

# If ts has cumulative confirmed but not new_cases, compute new_cases
if(!'new_cases' %in% names(ts) || all(is.na(ts$new_cases))){
  ts <- ts %>% group_by(country_region) %>% arrange(obs_date) %>%
    mutate(new_cases = confirmed - lag(confirmed)) %>% ungroup()
}

# Compute 7-day rolling averages per country
ts <- ts %>% group_by(country_region) %>% arrange(obs_date) %>%
  mutate(
    new_cases_7d = rollapplyr(new_cases, width = 7, FUN = function(x) mean(x, na.rm = TRUE), fill = NA, partial = TRUE),
    new_deaths = deaths - lag(deaths),
    new_deaths_7d = rollapplyr(new_deaths, width = 7, FUN = function(x) mean(x, na.rm = TRUE), fill = NA, partial = TRUE)
  ) %>% ungroup()

# SUMMARY METRICS (per country) using snapshot tables
summary_df <- world %>%
  select(country_region, population, total_cases, new_cases, total_deaths, total_recovered, total_tests, continent) %>%
  left_join(cwl %>% select(country_region, confirmed, deaths, recovered, active, new_cases_cwl = new_cases), by = 'country_region') %>%
  mutate(
    confirmed_final = coalesce(confirmed, total_cases),
    deaths_final = coalesce(deaths, total_deaths),
    recovered_final = coalesce(recovered, total_recovered),
    cfr = ifelse(is.finite(deaths_final) & !is.na(confirmed_final) & confirmed_final > 0, deaths_final / confirmed_final, NA_real_),
    incidence_per_100k = ifelse(!is.na(new_cases) & !is.na(population) & population>0, (new_cases / population) * 100000, NA_real_),
    deaths_per_100k = ifelse(!is.na(deaths_final) & !is.na(population) & population>0, (deaths_final / population) * 100000, NA_real_),
    recovery_pct = ifelse(!is.na(recovered_final) & !is.na(confirmed_final) & confirmed_final>0, recovered_final / confirmed_final, NA_real_)
  )

# POSITIVITY: only if total_tests present in worldometer and time-series tests exist we can compute delta tests; otherwise skip
summary_df <- summary_df %>% mutate(positivity = NA_real_)

# Disagreement: compare world.total_cases vs cwl.confirmed vs sum(ts.confirmed by country)
ts_agg <- ts %>% group_by(country_region) %>% summarise(ts_sum_confirmed = max(confirmed, na.rm = TRUE))
summary_df <- summary_df %>% left_join(ts_agg, by = 'country_region') %>%
  mutate(
    pct_diff_wm_cwl = ifelse(!is.na(total_cases) & !is.na(confirmed_final) & confirmed_final>0, (total_cases / confirmed_final - 1) * 100, NA_real_),
    pct_diff_wm_ts = ifelse(!is.na(total_cases) & !is.na(ts_sum_confirmed) & ts_sum_confirmed>0, (total_cases / ts_sum_confirmed - 1) * 100, NA_real_)
  )

# Create output directories
if(!dir.exists('r_scripts/plots')) dir.create('r_scripts/plots', recursive = TRUE)

# Plot 1: Top 20 CFR
p1 <- summary_df %>% filter(!is.na(cfr)) %>% arrange(desc(cfr)) %>% slice_head(n = 20) %>%
  ggplot(aes(x = reorder(country_region, cfr), y = cfr*100)) +
  geom_col(fill = '#D7261E') + coord_flip() +
  labs(title = 'Top 20 Case Fatality Rate (CFR)', y = 'CFR (%)', x = '') +
  scale_y_continuous(labels = scales::percent_format(scale = 1)) + theme_minimal()

ggsave('r_scripts/plots/cfr_top20.png', p1, width = 9, height = 7)

# Plot 2: incidence per 100k (top 20)
p2 <- summary_df %>% filter(!is.na(incidence_per_100k)) %>% arrange(desc(incidence_per_100k)) %>% slice_head(n = 20) %>%
  ggplot(aes(x = reorder(country_region, incidence_per_100k), y = incidence_per_100k)) + geom_col(fill = '#1F78B4') + coord_flip() +
  labs(title = 'New cases per 100k (latest snapshot)', y = 'New cases per 100k', x = '') + theme_minimal()

ggsave('r_scripts/plots/incidence_per_100k_top20.png', p2, width = 9, height = 7)

# Plot 3: deaths per 100k (top 20)
p3 <- summary_df %>% filter(!is.na(deaths_per_100k)) %>% arrange(desc(deaths_per_100k)) %>% slice_head(n = 20) %>%
  ggplot(aes(x = reorder(country_region, deaths_per_100k), y = deaths_per_100k)) + geom_col(fill = '#6A4C93') + coord_flip() +
  labs(title = 'Deaths per 100k (cumulative)', y = 'Deaths per 100k', x = '') + theme_minimal()

ggsave('r_scripts/plots/deaths_per_100k_top20.png', p3, width = 9, height = 7)

# Plot 4: time series new_cases_7d for top 6 countries by latest confirmed
top6 <- summary_df %>% arrange(desc(confirmed_final)) %>% slice_head(n = 6) %>% pull(country_region)

p4 <- ts %>% filter(country_region %in% top6) %>%
  ggplot(aes(x = obs_date, y = new_cases_7d, color = country_region)) + geom_line(size = 1) +
  labs(title = '7-day average new cases - top 6 countries', x = 'Date', y = 'New cases (7-day avg)', color = '') + theme_minimal() +
  scale_y_continuous(labels = comma)

ggsave('r_scripts/plots/new_cases_7d_top6.png', p4, width = 12, height = 6)

# Plot 5: disagreement scatter (worldometer vs country_wise_latest)
p5 <- summary_df %>% filter(!is.na(pct_diff_wm_cwl)) %>%
  ggplot(aes(x = confirmed_final, y = total_cases, label = country_region)) + geom_point(alpha = 0.6) +
  scale_x_log10(labels = comma) + scale_y_log10(labels = comma) +
  labs(title = 'Total cases: worldometer vs country_wise_latest', x = 'cwl.confirmed', y = 'wm.total_cases') + theme_minimal()

ggsave('r_scripts/plots/wm_vs_cwl_scatter.png', p5, width = 8, height = 6)

# Save summary
write.csv(summary_df, 'r_scripts/plots/summary_metrics.csv', row.names = FALSE)

cat('Epidemiology plots and summary written to r_scripts/plots/\n')

# Disconnect
dbDisconnect(con)
