-- Points percentage of each NHL team-season and of the same franchise the previous season.
-- 2004 is missing (lockout), so 2005 is paired with 2003.
SELECT year, franchID, tmID, G, Pts, GF, GA, playoff,
       Pts * 1.0 / (2 * G)                                              AS pts_pct,
       (GF - GA) * 1.0 / G                                              AS gd_per_game,
       LAG(year)                    OVER w                              AS prev_year,
       LAG(Pts * 1.0 / (2 * G))     OVER w                              AS pts_pct_prev,
       LAG((GF - GA) * 1.0 / G)     OVER w                              AS gd_per_game_prev
FROM Teams
WHERE lgID = 'NHL'
WINDOW w AS (PARTITION BY franchID ORDER BY year)
ORDER BY year, franchID;
