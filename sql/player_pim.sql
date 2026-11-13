-- Task (c): one row per NHL player-season (regular season only), with the target PIM of season t
-- and leak-free history known the day before season t.
--   * Stints are summed: a player traded mid-season has one row per team in Scoring.
--   * Target  : pim (regular-season PIM of season t). PostPIM (playoffs) is never used.
--   * History : lags from the player's own previous NHL season (2004 lockout: 2005 is paired with 2003),
--               career totals strictly before season t, and the t-1 PIM rate of the team he played for.
--   * Same-season columns (gp, g, a, pts, plus_minus, n_stints, franchID) are kept ONLY for analysis
--     (decomposition PIM = GP x PIM/GP); they are not known before season t and must not be features.
-- History is computed over the full NHL record (1917+) and the output is restricted to 1982-2009.

WITH stint AS (
    SELECT s.playerID, s.year, s.stint, s.tmID, t.franchID, s.pos,
           COALESCE(s.GP, 0)    AS gp,
           COALESCE(s.G, 0)     AS g,
           COALESCE(s.A, 0)     AS a,
           COALESCE(s.Pts, 0)   AS pts,
           COALESCE(s.PIM, 0)   AS pim,
           s."+/-"              AS plus_minus,
           ROW_NUMBER() OVER (PARTITION BY s.playerID, s.year ORDER BY COALESCE(s.GP, 0) DESC, s.stint) AS gp_rank
    FROM Scoring s
    JOIN Teams t ON s.year = t.year AND s.lgID = t.lgID AND s.tmID = t.tmID
    WHERE s.lgID = 'NHL'
      AND s.GP IS NOT NULL
      AND s.GP > 0
),
player_season AS (
    SELECT playerID, year,
           MAX(CASE WHEN gp_rank = 1 THEN pos END)      AS pos,
           MAX(CASE WHEN gp_rank = 1 THEN franchID END) AS franchID,
           COUNT(*)                                     AS n_stints,
           SUM(gp)  AS gp,
           SUM(g)   AS g,
           SUM(a)   AS a,
           SUM(pts) AS pts,
           SUM(pim) AS pim,
           SUM(plus_minus) AS plus_minus
    FROM stint
    GROUP BY playerID, year
),
team_pim AS (
    SELECT year, franchID,
           PIM * 1.0 / G AS team_pim_pg,
           PIM * 1.0 / G - AVG(PIM * 1.0 / G) OVER (PARTITION BY year) AS team_pim_pg_rel
    FROM Teams
    WHERE lgID = 'NHL'
),
league AS (
    SELECT year, SUM(PIM) * 1.0 / SUM(G) AS league_team_pim_pg
    FROM Teams
    WHERE lgID = 'NHL'
    GROUP BY year
),
hist AS (
    SELECT ps.*,
           LAG(year)            OVER w AS prev_year,
           LAG(gp)              OVER w AS gp_prev_raw,
           LAG(pim)             OVER w AS pim_prev_raw,
           LAG(pts)             OVER w AS pts_prev_raw,
           LAG(franchID)        OVER w AS franchID_prev_raw,
           LAG(year, 2)         OVER w AS prev2_year,
           LAG(pim, 2)          OVER w AS pim_prev2_raw,
           LAG(gp, 2)           OVER w AS gp_prev2_raw,
           COUNT(*)  OVER (w ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS seasons_before,
           SUM(gp)   OVER (w ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS career_gp_before,
           SUM(pim)  OVER (w ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS career_pim_before,
           SUM(pts)  OVER (w ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS career_pts_before
    FROM player_season ps
    WINDOW w AS (PARTITION BY playerID ORDER BY year)
),
flagged AS (
    SELECT h.*,
           CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003))
                THEN 1 ELSE 0 END AS played_prev
    FROM hist h
)
SELECT
    f.year, f.playerID,
    CASE WHEN f.pos LIKE 'G%' THEN 'G' WHEN f.pos LIKE 'D%' THEN 'D' ELSE 'F' END AS pos_group,
    f.pos,
    -- target and same-season columns (analysis only)
    f.pim, f.gp, f.g, f.a, f.pts, f.plus_minus, f.n_stints, f.franchID,
    f.pim * 1.0 / f.gp                                                         AS pim_pg,
    lg.league_team_pim_pg,
    -- player profile (Master), known before the season
    f.year - m.birthYear                                                       AS age,
    m.height, m.weight, m.shootCatch,
    -- previous season (only if the player played the previous NHL season)
    f.played_prev,
    CASE WHEN f.played_prev = 1 THEN f.gp_prev_raw  END                        AS gp_prev,
    CASE WHEN f.played_prev = 1 THEN f.pim_prev_raw END                        AS pim_prev,
    CASE WHEN f.played_prev = 1 THEN f.pts_prev_raw END                        AS pts_prev,
    CASE WHEN f.played_prev = 1 THEN f.pim_prev_raw * 1.0 / f.gp_prev_raw END  AS pim_pg_prev,
    CASE WHEN f.played_prev = 1 THEN f.pim_prev2_raw END                       AS pim_prev2,
    CASE WHEN f.played_prev = 1 AND f.gp_prev2_raw > 0
         THEN f.pim_prev2_raw * 1.0 / f.gp_prev2_raw END                       AS pim_pg_prev2,
    CASE WHEN f.played_prev = 1 THEN f.franchID_prev_raw END                   AS franchID_prev,
    -- career before season t
    COALESCE(f.seasons_before, 0)                                              AS seasons_before,
    COALESCE(f.career_gp_before, 0)                                            AS career_gp_before,
    COALESCE(f.career_pim_before, 0)                                           AS career_pim_before,
    f.career_pim_before * 1.0 / NULLIF(f.career_gp_before, 0)                  AS career_pim_pg_before,
    f.career_pts_before * 1.0 / NULLIF(f.career_gp_before, 0)                  AS career_pts_pg_before,
    -- team context at t-1 (team the player played most games for in t-1)
    tp.team_pim_pg     AS team_pim_pg_prev,
    tp.team_pim_pg_rel AS team_pim_pg_rel_prev
FROM flagged f
LEFT JOIN Master m   ON f.playerID = m.playerID
LEFT JOIN league lg  ON f.year = lg.year
LEFT JOIN team_pim tp
       ON f.played_prev = 1 AND tp.franchID = f.franchID_prev_raw AND tp.year = f.prev_year
WHERE f.year >= 1982
ORDER BY f.year, f.playerID;
