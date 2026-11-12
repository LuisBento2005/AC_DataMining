-- Leak-free per-team-season roster aggregations from Scoring, Master, AwardsPlayers, and HOF.
-- Includes:
--   * GP-weighted roster age and NHL experience (from Master)
--   * Team shooting% (SUM(G)/SUM(SOG)) and shots on goal (SOG)
--   * Scoring concentration (top-3 goal share) and scoring depth (count of 20+ goal scorers)
--   * Roster continuity (share of season s points & GP coming from players on the same franchise in s-1)
--   * Player awards won in season s, plus explicit HOF leakage check (already inducted vs future HOF induction)

WITH player_team AS (
    SELECT
        s.year,
        s.lgID,
        s.tmID,
        t.franchID,
        s.playerID,
        SUM(COALESCE(s.GP, 0))  AS gp,
        SUM(COALESCE(s.G, 0))   AS g,
        SUM(COALESCE(s.A, 0))   AS a,
        SUM(COALESCE(s.Pts, 0)) AS pts,
        SUM(COALESCE(s.PIM, 0)) AS pim,
        SUM(COALESCE(s.SOG, 0)) AS sog
    FROM Scoring s
    JOIN Teams t ON s.year = t.year AND s.lgID = t.lgID AND s.tmID = t.tmID
    WHERE s.lgID = 'NHL'
      AND s.year >= 1979
      AND COALESCE(s.GP, 0) > 0
    GROUP BY s.year, s.lgID, s.tmID, t.franchID, s.playerID
),
ranked_players AS (
    SELECT
        pt.*,
        m.birthYear,
        m.firstNHL,
        h.year AS hof_induction_year,
        ROW_NUMBER() OVER (PARTITION BY pt.year, pt.tmID ORDER BY pt.g DESC, pt.pts DESC, pt.playerID) AS goal_rank,
        SUM(pt.g) OVER (PARTITION BY pt.year, pt.tmID)                                                 AS team_player_g
    FROM player_team pt
    LEFT JOIN Master m ON pt.playerID = m.playerID
    LEFT JOIN HOF h    ON m.hofID = h.hofID
),
with_retention AS (
    SELECT
        cur.*,
        CASE WHEN prev.playerID IS NOT NULL THEN 1 ELSE 0 END AS is_returning
    FROM ranked_players cur
    LEFT JOIN player_team prev
        ON cur.franchID = prev.franchID
       AND cur.playerID = prev.playerID
       AND (cur.year - prev.year = 1 OR (cur.year = 2005 AND prev.year = 2003))
),
awards_per_player_season AS (
    SELECT year, lgID, playerID, COUNT(*) AS n_awards
    FROM AwardsPlayers
    WHERE lgID = 'NHL'
    GROUP BY year, lgID, playerID
)
SELECT
    r.year,
    r.lgID,
    r.tmID,
    r.franchID,
    COUNT(DISTINCT r.playerID)                                                                   AS roster_size,
    SUM(r.gp * (r.year - r.birthYear)) * 1.0 / NULLIF(SUM(CASE WHEN r.birthYear IS NOT NULL THEN r.gp END), 0) AS weighted_age,
    SUM(r.gp * (r.year - r.firstNHL))  * 1.0 / NULLIF(SUM(CASE WHEN r.firstNHL  IS NOT NULL THEN r.gp END), 0) AS weighted_exp,
    SUM(r.g) * 1.0 / NULLIF(SUM(r.sog), 0)                                                       AS shooting_pct,
    SUM(r.sog)                                                                                   AS roster_sog,
    SUM(CASE WHEN r.goal_rank <= 3 THEN r.g ELSE 0 END) * 1.0 / NULLIF(MAX(r.team_player_g), 0)  AS top3_goal_share,
    SUM(CASE WHEN r.g >= 20 THEN 1 ELSE 0 END)                                                   AS n_20g_scorers,
    SUM(CASE WHEN r.is_returning = 1 THEN r.pts ELSE 0 END) * 1.0 / NULLIF(SUM(r.pts), 0)        AS returning_pts_share,
    SUM(CASE WHEN r.is_returning = 1 THEN r.gp  ELSE 0 END) * 1.0 / NULLIF(SUM(r.gp), 0)         AS returning_gp_share,
    COALESCE(SUM(aw.n_awards), 0)                                                                AS player_awards,
    SUM(CASE WHEN r.hof_induction_year IS NOT NULL AND r.hof_induction_year < r.year THEN 1 ELSE 0 END)  AS hof_already_inducted,
    SUM(CASE WHEN r.hof_induction_year IS NOT NULL AND r.hof_induction_year >= r.year THEN 1 ELSE 0 END) AS hof_future_inducted_leak
FROM with_retention r
LEFT JOIN awards_per_player_season aw
    ON r.year = aw.year AND r.lgID = aw.lgID AND r.playerID = aw.playerID
WHERE r.year >= 1980
GROUP BY r.year, r.lgID, r.tmID, r.franchID
ORDER BY r.year, r.tmID;
