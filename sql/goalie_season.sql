-- Per-team-season goaltending metrics from Goalies (NHL, 1980–2009).
-- Note: Shots Against (SA) is recorded starting in 1982 (100% coverage in NHL 1982–2009).
-- Rows with NULL GP/SA in 1982 are goalies who only dressed in the playoffs; SUM() ignores NULLs safely.

SELECT
    g.year,
    g.lgID,
    g.tmID,
    COUNT(DISTINCT g.playerID)                                 AS n_goalies_used,
    SUM(g.GP)                                                  AS goalie_gp_sum,
    SUM(g.Min)                                                 AS goalie_min_sum,
    MAX(g.Min) * 1.0 / NULLIF(SUM(g.Min), 0)                   AS starter_min_share,
    SUM(g.GA)                                                  AS goalie_ga,
    SUM(g.SA)                                                  AS goalie_sa,
    1.0 - SUM(g.GA) * 1.0 / NULLIF(SUM(g.SA), 0)               AS save_pct,
    SUM(COALESCE(g.SHO, 0))                                    AS goalie_shutouts
FROM Goalies g
WHERE g.lgID = 'NHL'
  AND g.year >= 1980
GROUP BY g.year, g.lgID, g.tmID
ORDER BY g.year, g.tmID;
