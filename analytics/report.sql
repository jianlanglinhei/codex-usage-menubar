SELECT day AS utc_day, event, position, language, count
FROM event_counts
WHERE day >= date('now', '-29 days')
ORDER BY day DESC, event, position, language;
