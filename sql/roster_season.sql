-- Aggregated roster of each NHL franchise-season, built from the players who played for it.
-- Integration: Scoring (stats) + Master (birth year, weight) + AwardsPlayers (awards that season).
-- Used with a one-season lag: the roster of t-1 describes the team we know before season t.
WITH s AS (
    SELECT sc.playerID, sc.year, t.franchID,
           SUM(sc.GP) AS GP, SUM(sc.G) AS G, SUM(sc.A) AS A, SUM(sc.Pts) AS Pts,
           SUM(sc."+/-") AS pm, MAX(sc.pos) AS pos
    FROM Scoring sc
    JOIN Teams t ON t.year = sc.year AND t.tmID = sc.tmID AND t.lgID = sc.lgID
    WHERE sc.lgID = 'NHL'
    GROUP BY sc.playerID, sc.year, t.franchID
),
aw AS (SELECT DISTINCT playerID, year FROM AwardsPlayers WHERE lgID = 'NHL')
SELECT s.franchID, s.year,
       COUNT(*)                                                         AS n_players,
       SUM(s.Pts)                                                       AS roster_pts,
       MAX(s.Pts)                                                       AS top_scorer_pts,
       SUM(CASE WHEN s.G >= 20 THEN 1 ELSE 0 END)                       AS n_20goal,
       SUM(CASE WHEN s.Pts >= 60 THEN 1 ELSE 0 END)                     AS n_60pts,
       -- age at the start of the season, weighted by games played
       SUM(s.GP * (s.year - m.birthYear)) * 1.0 / NULLIF(SUM(CASE WHEN m.birthYear IS NOT NULL THEN s.GP END), 0) AS avg_age,
       SUM(s.GP * m.weight) * 1.0 / NULLIF(SUM(CASE WHEN m.weight IS NOT NULL THEN s.GP END), 0)                AS avg_weight,
       COUNT(aw.playerID)                                               AS n_award_winners
FROM s
LEFT JOIN Master m ON m.playerID = s.playerID
LEFT JOIN aw ON aw.playerID = s.playerID AND aw.year = s.year
GROUP BY s.franchID, s.year
ORDER BY s.franchID, s.year;
