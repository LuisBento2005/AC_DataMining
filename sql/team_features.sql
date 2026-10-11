-- Per-game team statistics for NHL seasons from 1967 (expansion era; power-play stats exist from 1963).
-- One row per team-season. Rates are per game so seasons of different length are comparable.
SELECT year, franchID, tmID, name, G,
       Pts * 1.0 / (2 * G)                          AS pts_pct,
       GF * 1.0 / G                                 AS gf_pg,
       GA * 1.0 / G                                 AS ga_pg,
       (GF - GA) * 1.0 / G                          AS gd_pg,
       PIM * 1.0 / G                                AS pim_pg,
       PPG * 1.0 / NULLIF(PPC, 0)                   AS pp_pct,      -- power-play conversion
       1 - PKG * 1.0 / NULLIF(PKC, 0)               AS pk_pct,      -- penalty-kill success
       PPC * 1.0 / G                                AS pp_opp_pg,   -- power-play chances drawn
       SHF * 1.0 / G                                AS shf_pg,      -- short-handed goals for
       -- Pythagorean expectation: share of points a team "should" get from its goals
       GF * GF * 1.0 / (GF * GF + GA * GA)          AS pyth_pct,
       CASE WHEN playoff IS NULL THEN 0 ELSE 1 END  AS made_playoffs
FROM Teams
WHERE lgID = 'NHL' AND year >= 1967
ORDER BY year, franchID;
