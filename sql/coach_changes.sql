-- One row per NHL team-season with coach-change flags.
-- Teams are followed across seasons by franchID (tmID changes on relocation).
-- changed_between: the coach who started season t is not the coach who ended season t-1.
--                  NULL when there is no previous season, or when the previous row is not
--                  the previous season (gap in the franchise's history). 2004 has no season
--                  (lockout), so 2005 is compared with 2003.
-- changed_during:  the team had a second stint in season t (mid-season change).
--
-- Notes from data quality:
--   * Coaches.stint is the order of the coaches within a season (1 = opening coach).
--     Co-coaches share a stint (Detroit 1998: Lewis and Smith, both stint 1), so a
--     mid-season change is MAX(stint) > 1, not COUNT(*) > 1.
--   * The same coach can have two rows in one season (e.g. Buffalo 1981, Bowman), so
--     n_coaches counts DISTINCT coaches.
--   * Ties between co-coaches are broken by games coached, then coachID, so first_coach
--     and last_coach are deterministic.
WITH c AS (
    SELECT t.franchID, c.year, c.coachID, c.stint, c.g,
           ROW_NUMBER() OVER (PARTITION BY t.franchID, c.year
                              ORDER BY c.stint ASC,  c.g DESC, c.coachID) AS rn_first,
           ROW_NUMBER() OVER (PARTITION BY t.franchID, c.year
                              ORDER BY c.stint DESC, c.g DESC, c.coachID) AS rn_last
    FROM Coaches c
    JOIN Teams t ON t.year = c.year AND t.tmID = c.tmID AND t.lgID = c.lgID
    WHERE c.lgID = 'NHL'
),
first_last AS (
    SELECT franchID, year,
           COUNT(DISTINCT coachID)                      AS n_coaches,
           MAX(stint)                                   AS n_stints,
           MAX(CASE WHEN rn_first = 1 THEN coachID END) AS first_coach,
           MAX(CASE WHEN rn_last  = 1 THEN coachID END) AS last_coach
    FROM c
    GROUP BY franchID, year
),
with_prev AS (
    SELECT *,
           LAG(year)       OVER w AS prev_year,
           LAG(last_coach) OVER w AS prev_last_coach
    FROM first_last
    WINDOW w AS (PARTITION BY franchID ORDER BY year)
)
SELECT franchID, year, n_coaches, n_stints, first_coach, last_coach, prev_year, prev_last_coach,
       CASE WHEN prev_year IS NULL THEN NULL
            WHEN NOT (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN NULL
            WHEN first_coach <> prev_last_coach THEN 1 ELSE 0 END AS changed_between,
       CASE WHEN n_stints > 1 THEN 1 ELSE 0 END                 AS changed_during
FROM with_prev
ORDER BY franchID, year;
