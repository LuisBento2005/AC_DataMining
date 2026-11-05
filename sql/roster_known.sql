-- OPTIONAL features, only valid if the professor confirms the roster of season t is known
-- the day before the season. For every player who plays for the franchise in season t,
-- take HIS statistics from the previous season (on any team).
-- Caveat: players acquired mid-season also appear in the season-t roster (small leak).
-- 2004 is missing (lockout), so the season before 2005 is 2003.
WITH r AS (
    SELECT DISTINCT sc.playerID, sc.year, t.franchID,
           CASE WHEN sc.year = 2005 THEN 2003 ELSE sc.year - 1 END AS prev_year
    FROM Scoring sc
    JOIN Teams t ON t.year = sc.year AND t.tmID = sc.tmID AND t.lgID = sc.lgID
    WHERE sc.lgID = 'NHL'
),
p AS (
    SELECT playerID, year, SUM(GP) AS GP, SUM(G) AS G, SUM(Pts) AS Pts
    FROM Scoring WHERE lgID = 'NHL' GROUP BY playerID, year
)
SELECT r.franchID, r.year,
       SUM(COALESCE(p.Pts, 0))                                    AS rk_prev_pts,
       SUM(CASE WHEN p.G >= 20 THEN 1 ELSE 0 END)                  AS rk_n20goal,
       AVG(CASE WHEN p.playerID IS NULL THEN 1.0 ELSE 0.0 END)     AS rk_share_rookies,
       AVG(CASE WHEN r2.playerID IS NOT NULL THEN 1.0 ELSE 0.0 END) AS rk_share_returning
FROM r
LEFT JOIN p  ON p.playerID = r.playerID AND p.year = r.prev_year
LEFT JOIN r r2 ON r2.playerID = r.playerID AND r2.year = r.prev_year AND r2.franchID = r.franchID
GROUP BY r.franchID, r.year
ORDER BY r.franchID, r.year;
