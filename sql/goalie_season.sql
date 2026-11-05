-- Goaltending of each NHL franchise-season.
-- Integration: Goalies + Teams. Save% = 1 - GA / SA (shots against are only recorded from 1982).
WITH g AS (
    SELECT gl.playerID, gl.year, t.franchID, SUM(gl.Min) AS Min, SUM(gl.GA) AS GA, SUM(gl.SA) AS SA
    FROM Goalies gl
    JOIN Teams t ON t.year = gl.year AND t.tmID = gl.tmID AND t.lgID = gl.lgID
    WHERE gl.lgID = 'NHL'
    GROUP BY gl.playerID, gl.year, t.franchID
),
ranked AS (
    SELECT g.*, ROW_NUMBER() OVER (PARTITION BY franchID, year ORDER BY Min DESC) AS rn FROM g
)
SELECT franchID, year,
       1 - SUM(GA) * 1.0 / NULLIF(SUM(SA), 0)                                   AS team_sv_pct,
       MAX(CASE WHEN rn = 1 THEN 1 - GA * 1.0 / NULLIF(SA, 0) END)              AS main_goalie_sv_pct,
       MAX(CASE WHEN rn = 1 THEN Min END) * 1.0 / NULLIF(SUM(Min), 0)           AS main_goalie_share,
       COUNT(*)                                                                 AS n_goalies
FROM ranked
GROUP BY franchID, year
ORDER BY franchID, year;
