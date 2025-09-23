
-- Top 10 countries/regions with the highest death rates (deaths/confirmed cases) where confirmed cases are greater than 1000
SELECT 
    country_region,
    ROUND((SUM(deaths)::numeric / SUM(confirmed)), 2) AS death_rate
    FROM covid_data
    WHERE confirmed > 1000
    GROUP BY country_region, province_state
    ORDER BY death_rate DESC
    LIMIT 10;

--Importing worldometer data
SELECT 
    country_region,
    continent,
    population,
    new_cases,
    total_cases,
    new_deaths,
    total_deaths,
    total_recovered,
    active_cases,
    tot_cases_1m_pop,
    deaths_1m_pop
FROM worldometer_data
ORDER BY total_cases DESC
LIMIT 10;

-- Top 10 countries from country_wise_latest by confirmed cases
SELECT 
    country_region,
    confirmed,
    deaths,
    recovered,
    active,
    new_cases,
    deaths_per_100_cases,
    who_region
FROM country_wise_latest
ORDER BY confirmed DESC
LIMIT 10;

-- Comprehensive join of all three COVID data tables
SELECT 
    cd.country_region,
    cd.province_state,
    SUM(cd.confirmed) as covid_data_confirmed,
    SUM(cd.deaths) as covid_data_deaths,
    wm.total_cases as worldometer_total_cases,
    wm.total_deaths as worldometer_total_deaths,
    wm.continent,
    wm.population,
    cwl.new_cases as country_wise_new_cases,
    cwl.confirmed as country_wise_confirmed,
    cwl.deaths as country_wise_deaths,
    cwl.recovered as country_wise_recovered,
    cwl.who_region,
    cwl.deaths_per_100_cases
FROM covid_data cd
FULL OUTER JOIN worldometer_data wm ON cd.country_region = wm.country_region
FULL OUTER JOIN country_wise_latest cwl ON cd.country_region = cwl.country_region
GROUP BY cd.country_region, cd.province_state, wm.total_cases, wm.total_deaths, 
         wm.continent, wm.population, cwl.new_cases, cwl.confirmed, cwl.deaths, cwl.recovered, 
         cwl.who_region, cwl.deaths_per_100_cases
ORDER BY covid_data_confirmed DESC NULLS LAST
LIMIT 15;

-- Countries appearing in all three datasets
SELECT 
    cd.country_region,
    ROUND((SUM(cd.deaths)::numeric / SUM(cd.confirmed)), 2) AS death_rate,
    ROUND((cwl.new_cases::numeric / wm.population) * 100000, 2) AS incidence_per_100k,
    SUM(cd.confirmed) as covid_data_total,
    wm.total_cases as worldometer_total,
    cwl.confirmed as country_wise_total,
    wm.continent,
    cwl.who_region
FROM covid_data cd
INNER JOIN worldometer_data wm ON cd.country_region = wm.country_region
INNER JOIN country_wise_latest cwl ON cd.country_region = cwl.country_region
GROUP BY cd.country_region, wm.total_cases, cwl.confirmed, wm.continent, cwl.who_region, wm.new_cases, wm.population, cwl.new_cases
ORDER BY death_rate DESC
LIMIT 10;
