SELECT 
    country_region,
    ROUND((SUM(deaths)::numeric / SUM(confirmed)), 2) AS death_rate
    FROM covid_data
    WHERE confirmed > 1000
    GROUP BY country_region, province_state
    ORDER BY death_rate DESC
    LIMIT 10;