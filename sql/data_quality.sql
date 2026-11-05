-- Data quality checks (one query per block, separated by a line with "-- @check <name>").

-- @check uniqueness_teams: duplicate (year, tmID, lgID) in Teams
SELECT year, tmID, lgID, COUNT(*) AS n FROM Teams GROUP BY year, tmID, lgID HAVING n > 1;

-- @check uniqueness_master: people with the same name and birth date (possible duplicates)
SELECT firstName, lastName, birthYear, birthMon, birthDay, COUNT(*) AS n
FROM Master WHERE birthYear IS NOT NULL
GROUP BY firstName, lastName, birthYear, birthMon, birthDay HAVING n > 1;

-- @check consistency_games: W + L + T + OTL must equal G
SELECT year, tmID, G, W, L, T, OTL, W + L + COALESCE(T,0) + COALESCE(OTL,0) AS sum_results
FROM Teams WHERE lgID = 'NHL' AND W + L + COALESCE(T,0) + COALESCE(OTL,0) <> G;

-- @check consistency_points: Pts must equal 2W + T + OTL
SELECT year, tmID, Pts, 2*W + COALESCE(T,0) + COALESCE(OTL,0) AS expected
FROM Teams WHERE lgID = 'NHL' AND Pts <> 2*W + COALESCE(T,0) + COALESCE(OTL,0);

-- @check consistency_coach_games: the games of a team's coaches must add up to the team's games
SELECT t.year, t.tmID, t.G, SUM(c.g) AS coach_g
FROM Teams t JOIN Coaches c ON c.year = t.year AND c.tmID = t.tmID AND c.lgID = t.lgID
WHERE t.lgID = 'NHL'
GROUP BY t.year, t.tmID HAVING SUM(c.g) <> t.G;

-- @check accuracy_goals: team GF in Teams vs the sum of its players' goals in Scoring
SELECT t.year, t.tmID, t.GF, SUM(s.G) AS player_goals, t.GF - SUM(s.G) AS diff
FROM Teams t JOIN Scoring s ON s.year = t.year AND s.tmID = t.tmID AND s.lgID = t.lgID
WHERE t.lgID = 'NHL' AND t.year >= 1979
GROUP BY t.year, t.tmID HAVING ABS(t.GF - SUM(s.G)) > 2;

-- @check validity_values: negative counts or ranks out of range
SELECT year, tmID, G, W, L, GF, GA, rank FROM Teams
WHERE lgID = 'NHL' AND (G <= 0 OR W < 0 OR L < 0 OR GF < 0 OR GA < 0 OR rank < 1 OR rank > 8);

-- @check validity_save_pct: impossible goalie lines (more goals than shots)
SELECT playerID, year, tmID, GA, SA FROM Goalies WHERE lgID = 'NHL' AND SA IS NOT NULL AND GA > SA;

-- @check timeliness_coverage: years covered by each table
SELECT 'Teams' AS tbl, MIN(year) AS first, MAX(year) AS last, COUNT(DISTINCT year) AS n_years FROM Teams
UNION ALL SELECT 'Scoring', MIN(year), MAX(year), COUNT(DISTINCT year) FROM Scoring
UNION ALL SELECT 'Goalies', MIN(year), MAX(year), COUNT(DISTINCT year) FROM Goalies
UNION ALL SELECT 'Coaches', MIN(year), MAX(year), COUNT(DISTINCT year) FROM Coaches
UNION ALL SELECT 'TeamSplits', MIN(year), MAX(year), COUNT(DISTINCT year) FROM TeamSplits
UNION ALL SELECT 'TeamsHalf', MIN(year), MAX(year), COUNT(DISTINCT year) FROM TeamsHalf
UNION ALL SELECT 'ScoringSup', MIN(year), MAX(year), COUNT(DISTINCT year) FROM ScoringSup
UNION ALL SELECT 'GoaliesShootout', MIN(year), MAX(year), COUNT(DISTINCT year) FROM GoaliesShootout
UNION ALL SELECT 'AwardsPlayers', MIN(year), MAX(year), COUNT(DISTINCT year) FROM AwardsPlayers
UNION ALL SELECT 'AwardsCoaches', MIN(year), MAX(year), COUNT(DISTINCT year) FROM AwardsCoaches;
