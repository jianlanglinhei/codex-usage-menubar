CREATE TABLE IF NOT EXISTS event_counts (
  day TEXT NOT NULL,
  event TEXT NOT NULL CHECK (event IN ('install_click', 'install_copy', 'source_click')),
  position TEXT NOT NULL,
  language TEXT NOT NULL CHECK (language IN ('zh', 'en')),
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, event, position, language)
);
