-- Home vs Road and Early-season (Oct-Dec) vs Late-season (Feb-Apr) splits from TeamSplits.
-- Points formula: 2*W + T + OTL, divided by 2*G for that split.

WITH raw_splits AS (
    SELECT
        ts.year,
        ts.lgID,
        ts.tmID,
        -- Home games and points
        (COALESCE(ts.hW, 0) + COALESCE(ts.hL, 0) + COALESCE(ts.hT, 0) + COALESCE(ts.hOTL, 0)) AS home_g,
        (2 * COALESCE(ts.hW, 0) + COALESCE(ts.hT, 0) + COALESCE(ts.hOTL, 0))                  AS home_pts,
        -- Road games and points
        (COALESCE(ts.rW, 0) + COALESCE(ts.rL, 0) + COALESCE(ts.rT, 0) + COALESCE(ts.rOTL, 0)) AS road_g,
        (2 * COALESCE(ts.rW, 0) + COALESCE(ts.rT, 0) + COALESCE(ts.rOTL, 0))                  AS road_pts,
        -- Early season (Sep + Oct + Nov + Dec + Jan; includes Jan so the 1994 lockout 48-game season is covered)
        (COALESCE(ts.SepW,0)+COALESCE(ts.OctW,0)+COALESCE(ts.NovW,0)+COALESCE(ts.DecW,0)+COALESCE(ts.JanW,0)
         + COALESCE(ts.SepL,0)+COALESCE(ts.OctL,0)+COALESCE(ts.NovL,0)+COALESCE(ts.DecL,0)+COALESCE(ts.JanL,0)
         + COALESCE(ts.SepT,0)+COALESCE(ts.OctT,0)+COALESCE(ts.NovT,0)+COALESCE(ts.DecT,0)+COALESCE(ts.JanT,0)
         + COALESCE(ts.SepOL,0)+COALESCE(ts.OctOL,0)+COALESCE(ts.NovOL,0)+COALESCE(ts.DecOL,0)+COALESCE(ts.JanOL,0)) AS early_g,
        (2*(COALESCE(ts.SepW,0)+COALESCE(ts.OctW,0)+COALESCE(ts.NovW,0)+COALESCE(ts.DecW,0)+COALESCE(ts.JanW,0))
         + COALESCE(ts.SepT,0)+COALESCE(ts.OctT,0)+COALESCE(ts.NovT,0)+COALESCE(ts.DecT,0)+COALESCE(ts.JanT,0)
         + COALESCE(ts.SepOL,0)+COALESCE(ts.OctOL,0)+COALESCE(ts.NovOL,0)+COALESCE(ts.DecOL,0)+COALESCE(ts.JanOL,0)) AS early_pts,
        -- Late season (Feb + Mar + Apr)
        (COALESCE(ts.FebW,0)+COALESCE(ts.MarW,0)+COALESCE(ts.AprW,0)
         + COALESCE(ts.FebL,0)+COALESCE(ts.MarL,0)+COALESCE(ts.AprL,0)
         + COALESCE(ts.FebT,0)+COALESCE(ts.MarT,0)+COALESCE(ts.AprT,0)
         + COALESCE(ts.FebOL,0)+COALESCE(ts.MarOL,0)+COALESCE(ts.AprOL,0))                    AS late_g,
        (2*(COALESCE(ts.FebW,0)+COALESCE(ts.MarW,0)+COALESCE(ts.AprW,0))
         + COALESCE(ts.FebT,0)+COALESCE(ts.MarT,0)+COALESCE(ts.AprT,0)
         + COALESCE(ts.FebOL,0)+COALESCE(ts.MarOL,0)+COALESCE(ts.AprOL,0))                    AS late_pts
    FROM TeamSplits ts
    WHERE ts.lgID = 'NHL'
      AND ts.year >= 1980
)
SELECT
    year,
    lgID,
    tmID,
    home_pts * 1.0 / NULLIF(2 * home_g, 0)                                                    AS home_pts_pct,
    road_pts * 1.0 / NULLIF(2 * road_g, 0)                                                    AS road_pts_pct,
    (home_pts * 1.0 / NULLIF(2 * home_g, 0)) - (road_pts * 1.0 / NULLIF(2 * road_g, 0))       AS home_road_gap,
    early_pts * 1.0 / NULLIF(2 * early_g, 0)                                                  AS early_pts_pct,
    late_pts * 1.0 / NULLIF(2 * late_g, 0)                                                    AS late_pts_pct,
    (late_pts * 1.0 / NULLIF(2 * late_g, 0)) - (early_pts * 1.0 / NULLIF(2 * early_g, 0))     AS late_surge
FROM raw_splits
ORDER BY year, tmID;
