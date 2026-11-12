-- Playoff depth/workload (Teams, TeamsPost) and Division Strength of Schedule (Teams, TeamVsTeam).
-- Notes:
--   * Playoff round ordinal (0 = missed, 1..4 = eliminated in round 1..4, 5 = won Stanley Cup).
--   * div_rivals_pts_pct and div_rivals_pts_pct_rel measure the strength of the other teams in the same division.
--   * vs_div_pts_pct measures the team's actual points% against division rivals from TeamVsTeam.

WITH base_teams AS (
    SELECT
        t.year,
        t.lgID,
        t.tmID,
        t.franchID,
        t.confID,
        t.divID,
        t.G,
        t.Pts * 1.0 / (2 * t.G) AS pts_pct,
        (t.Pts * 1.0 / (2 * t.G)) - AVG(t.Pts * 1.0 / (2 * t.G)) OVER (PARTITION BY t.year) AS pts_pct_rel,
        (t.GF - t.GA) * 1.0 / t.G AS gd_pg,
        t.playoff,
        CASE
            WHEN t.playoff IS NULL THEN 0
            WHEN t.playoff IN ('PRE', 'DF', 'DSF', 'CQF') THEN 1
            WHEN t.playoff IN ('QF', 'CSF') THEN 2
            WHEN t.playoff IN ('SF', 'CF') THEN 3
            WHEN t.playoff = 'F' THEN 4
            WHEN t.playoff = 'SC' THEN 5
            ELSE 0
        END AS playoff_round
    FROM Teams t
    WHERE t.lgID = 'NHL'
      AND t.year >= 1980
),
div_rivals AS (
    SELECT
        a.year,
        a.tmID,
        AVG(b.pts_pct)     AS div_rivals_pts_pct,
        AVG(b.pts_pct_rel) AS div_rivals_pts_pct_rel,
        AVG(b.gd_pg)       AS div_rivals_gd_pg
    FROM base_teams a
    JOIN base_teams b
        ON a.year = b.year
       AND a.divID = b.divID
       AND a.franchID <> b.franchID
    GROUP BY a.year, a.tmID
),
vs_div AS (
    SELECT
        tvt.year,
        tvt.tmID,
        (2 * SUM(tvt.W) + SUM(COALESCE(tvt.T, 0)) + SUM(COALESCE(tvt.OTL, 0))) * 1.0
        / NULLIF(2 * SUM(tvt.W + tvt.L + COALESCE(tvt.T, 0) + COALESCE(tvt.OTL, 0)), 0) AS vs_div_pts_pct
    FROM TeamVsTeam tvt
    JOIN base_teams self ON tvt.year = self.year AND tvt.tmID = self.tmID
    JOIN base_teams opp  ON tvt.year = opp.year  AND tvt.oppID = opp.tmID
    WHERE tvt.lgID = 'NHL'
      AND self.divID = opp.divID
    GROUP BY tvt.year, tvt.tmID
)
SELECT
    bt.year,
    bt.lgID,
    bt.tmID,
    bt.franchID,
    bt.confID,
    bt.divID,
    bt.playoff_round,
    CASE WHEN bt.playoff_round > 0 THEN 1 ELSE 0 END          AS made_playoffs,
    COALESCE(tp.G, 0)                                         AS post_games,
    CASE WHEN COALESCE(tp.G, 0) > 0 THEN tp.W * 1.0 / tp.G ELSE 0.0 END AS post_win_pct,
    dr.div_rivals_pts_pct,
    dr.div_rivals_pts_pct_rel,
    dr.div_rivals_gd_pg,
    vd.vs_div_pts_pct
FROM base_teams bt
LEFT JOIN TeamsPost tp ON bt.year = tp.year AND bt.lgID = tp.lgID AND bt.tmID = tp.tmID
LEFT JOIN div_rivals dr ON bt.year = dr.year AND bt.tmID = dr.tmID
LEFT JOIN vs_div vd     ON bt.year = vd.year AND bt.tmID = vd.tmID
ORDER BY bt.year, bt.tmID;
