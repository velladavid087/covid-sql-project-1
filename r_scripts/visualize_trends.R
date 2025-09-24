# Visualize COVID-19 trends from the local Postgres `covid` database
# Requires: R >= 4.0, packages: DBI, RPostgres, dplyr, lubridate, ggplot2, scales

library(DBI)
library(RPostgres)
library(dplyr)
library(lubridate)
library(ggplot2)
library(scales)

# Connection settings - adjust if needed
con <- dbConnect(RPostgres::Postgres(), dbname = "covid", user = "vella87")

# Query: robust column selection using COALESCE for common column name variants
q <- "
SELECT
  COALESCE(observation_date, date, dt) AS obs_date,
  COALESCE(country_region, country, countryregion, country_name) AS country_region,
  COALESCE(province_state, province, state) AS province_state,
  COALESCE(confirmed, total_cases, confirmed_cases) AS confirmed,
  COALESCE(deaths, total_deaths) AS deaths
FROM covid_data
WHERE COALESCE(observation_date, date, dt) IS NOT NULL
ORDER BY country_region, COALESCE(observation_date, date, dt)
"

# Pull data
df <- dbGetQuery(con, q)

# Basic cleanup
df <- df %>%
  mutate(
    obs_date = as.Date(obs_date),
    country_region = as.character(country_region),
    province_state = as.character(province_state),
    confirmed = as.integer(confirmed),
    deaths = as.integer(deaths)
  ) %>%
  arrange(country_region, obs_date)

# Compute daily new cases if confirmed is cumulative
if(!"new_cases" %in% names(df)){
  df <- df %>%
    group_by(country_region) %>%
    mutate(new_cases = confirmed - lag(confirmed, default = NA_integer_)) %>%
    ungroup()
}

# 7-day rolling average
df <- df %>%
  group_by(country_region) %>%
  arrange(obs_date) %>%
  mutate(
    new_cases_7d = zoo::rollapply(new_cases, width = 7, FUN = function(x) mean(x, na.rm = TRUE), align = 'right', fill = NA, partial = TRUE),
    deaths_7d = zoo::rollapply(deaths - lag(deaths, default = NA_integer_), width = 7, FUN = function(x) mean(x, na.rm = TRUE), align = 'right', fill = NA, partial = TRUE)
  ) %>%
  ungroup()

# Example country list - top 6 by latest confirmed
latest <- df %>% filter(!is.na(confirmed)) %>% group_by(country_region) %>% summarise(latest_confirmed = max(confirmed, na.rm = TRUE)) %>% arrange(desc(latest_confirmed)) %>% slice_head(n = 6)

plot_countries <- latest$country_region

p <- df %>% filter(country_region %in% plot_countries) %>%
  ggplot(aes(x = obs_date, y = new_cases_7d, color = country_region)) +
  geom_line(size = 1) +
  labs(title = '7-day average of new cases', x = 'Date', y = 'New cases (7-day avg)', color = 'Country') +
  scale_y_continuous(labels = scales::comma) +
  theme_minimal()

# Save plot
ggsave(filename = 'r_scripts/new_cases_7d_top6.png', plot = p, width = 12, height = 6, dpi = 150)

# Also save a CSV summary
summary_df <- df %>% group_by(country_region) %>% summarise(latest_date = max(obs_date, na.rm = TRUE), latest_confirmed = max(confirmed, na.rm = TRUE), latest_new_cases_7d = last(na.omit(new_cases_7d)))
write.csv(summary_df, file = 'r_scripts/country_summary.csv', row.names = FALSE)

cat('Plots and summary saved to r_scripts/\n')

# Disconnect
dbDisconnect(con)
