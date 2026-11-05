-- One row per NHL franchise-season: who started the season, who finished it,
-- and whether the coach changed during the season.
-- Coaches.stint is the order of the coaches of a team within a season (1 = opening coach).
-- Co-coaches share the same stint (Detroit 1998), so a mid-season change is
-- MAX(stint) > 1, not COUNT(*) > 1.
-- Teams are followed by franchID because tmID changes when a team relocates.
WITH c AS (
    SELECT t.franchID, c.year, c.coachID, c.stint, c.g,
           ROW_NUMBER() OVER (PARTITION BY t.franchID, c.year ORDER BY c.stint ASC,  c.g DESC) AS rn_first,
           ROW_NUMBER() OVER (PARTITION BY t.franchID, c.year ORDER BY c.stint DESC, c.g DESC) AS rn_last
    FROM Coaches c
    JOIN Teams t ON t.year = c.year AND t.tmID = c.tmID AND t.lgID = c.lgID
    WHERE c.lgID = 'NHL'
)
SELECT franchID, year,
       MAX(stint)                                   AS n_stints,
       COUNT(DISTINCT coachID)                      AS n_coaches,
       MAX(CASE WHEN rn_first = 1 THEN coachID END) AS first_coach,
       MAX(CASE WHEN rn_last  = 1 THEN coachID END) AS last_coach,
       CASE WHEN MAX(stint) > 1 THEN 1 ELSE 0 END   AS changed_during
FROM c
GROUP BY franchID, year
ORDER BY franchID, year;
