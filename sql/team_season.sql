-- One row per NHL team-season: raw counts, per-game rates and business concepts.
-- Integration: Teams + TeamSplits (home/road and month-by-month results).
-- Rates are per game, so seasons of different length (48 to 84 games) are comparable.
-- T (ties) and OTL (overtime losses) mean different things across eras; both are a
-- "non-win, non-regulation-loss" worth one point, so they are merged into one column.
SELECT t.year, t.franchID, t.tmID, t.name, t.confID, t.divID, t.rank AS div_rank, t.playoff,
       t.G, t.W, t.L,
       COALESCE(t.T, 0) + COALESCE(t.OTL, 0)                 AS ties_otl,
       t.Pts, t.GF, t.GA, t.PIM, t.PPG, t.PPC, t.PKG, t.PKC, t.SHF, t.SHA,
       t.Pts * 1.0 / (2 * t.G)                               AS pts_pct,
       t.W * 1.0 / t.G                                       AS win_pct,
       t.GF * 1.0 / t.G                                      AS gf_pg,
       t.GA * 1.0 / t.G                                      AS ga_pg,
       (t.GF - t.GA) * 1.0 / t.G                             AS gd_pg,
       -- Pythagorean expectation: the share of points a team "deserved" from its goals
       t.GF * t.GF * 1.0 / (t.GF * t.GF + t.GA * t.GA)       AS pyth_pct,
       t.PIM * 1.0 / t.G                                     AS pim_pg,
       t.PPG * 1.0 / NULLIF(t.PPC, 0)                        AS pp_pct,
       1 - t.PKG * 1.0 / NULLIF(t.PKC, 0)                    AS pk_pct,
       t.PPC * 1.0 / t.G                                     AS pp_opp_pg,
       (t.SHF - t.SHA) * 1.0 / t.G                           AS sh_diff_pg,
       -- home / road strength
       s.hW * 1.0 / NULLIF(s.hW + s.hL + COALESCE(s.hT,0) + COALESCE(s.hOTL,0), 0) AS home_win_pct,
       s.rW * 1.0 / NULLIF(s.rW + s.rL + COALESCE(s.rT,0) + COALESCE(s.rOTL,0), 0) AS road_win_pct,
       -- form in the second half of the season (January to April)
       (COALESCE(s.JanW,0)+COALESCE(s.FebW,0)+COALESCE(s.MarW,0)+COALESCE(s.AprW,0)) * 1.0 /
       NULLIF(COALESCE(s.JanW,0)+COALESCE(s.JanL,0)+COALESCE(s.JanT,0)+COALESCE(s.JanOL,0)
            + COALESCE(s.FebW,0)+COALESCE(s.FebL,0)+COALESCE(s.FebT,0)+COALESCE(s.FebOL,0)
            + COALESCE(s.MarW,0)+COALESCE(s.MarL,0)+COALESCE(s.MarT,0)+COALESCE(s.MarOL,0)
            + COALESCE(s.AprW,0)+COALESCE(s.AprL,0)+COALESCE(s.AprT,0)+COALESCE(s.AprOL,0), 0) AS late_win_pct,
       CASE WHEN t.playoff IS NULL THEN 0 ELSE 1 END                                 AS made_playoffs,
       -- how far the team went in the playoffs (0 = missed, 5 = won the Stanley Cup)
       CASE WHEN t.playoff IS NULL THEN 0
            WHEN t.playoff IN ('PRE','DSF','CQF') THEN 1
            WHEN t.playoff IN ('QF','DF','CSF')   THEN 2
            WHEN t.playoff IN ('SF','CF')         THEN 3
            WHEN t.playoff = 'F'                  THEN 4
            WHEN t.playoff = 'SC'                 THEN 5 END                         AS playoff_depth
FROM Teams t
LEFT JOIN TeamSplits s ON s.year = t.year AND s.tmID = t.tmID AND s.lgID = t.lgID
WHERE t.lgID = 'NHL'
ORDER BY t.year, t.franchID;
