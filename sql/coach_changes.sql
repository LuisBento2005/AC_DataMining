-- One row per NHL team-season with coach-change flags.
-- Teams are followed across seasons by franchID (tmID changes on relocation).
-- changed_between: the coach who started season t is not the coach who ended season t-1.
-- changed_during:  more than one coach in season t (mid-season firing).
WITH coach_season AS (
    SELECT t.franchID, c.year,
           COUNT(*) AS n_coaches,
           MIN(c.stint) AS first_stint,
           MAX(c.stint) AS last_stint
    FROM Coaches c
    JOIN Teams t ON t.year = c.year AND t.tmID = c.tmID AND t.lgID = c.lgID
    WHERE c.lgID = 'NHL'
    GROUP BY t.franchID, c.year
),
first_last AS (
    SELECT cs.franchID, cs.year, cs.n_coaches,
           (SELECT c.coachID FROM Coaches c JOIN Teams t ON t.year = c.year AND t.tmID = c.tmID AND t.lgID = c.lgID
             WHERE t.franchID = cs.franchID AND c.year = cs.year AND c.stint = cs.first_stint) AS first_coach,
           (SELECT c.coachID FROM Coaches c JOIN Teams t ON t.year = c.year AND t.tmID = c.tmID AND t.lgID = c.lgID
             WHERE t.franchID = cs.franchID AND c.year = cs.year AND c.stint = cs.last_stint) AS last_coach
    FROM coach_season cs
)
SELECT franchID, year, n_coaches, first_coach, last_coach,
       LAG(year)       OVER w AS prev_year,
       LAG(last_coach) OVER w AS prev_last_coach,
       CASE WHEN LAG(last_coach) OVER w IS NULL THEN NULL
            WHEN first_coach <> LAG(last_coach) OVER w THEN 1 ELSE 0 END AS changed_between,
       CASE WHEN n_coaches > 1 THEN 1 ELSE 0 END AS changed_during
FROM first_last
WINDOW w AS (PARTITION BY franchID ORDER BY year)
ORDER BY franchID, year;
