--one row per team-season with the coach who started it, stint 1
SELECT c.coachID, c.year, c.lgID,
t.franchID, c.tmID, c.stint
FROM Coaches c
JOIN Teams t ON t.year = c.year AND t.tmID = c.tmID AND t.lgID = c.lgID
WHERE c.stint = 1
GROUP BY c.coachID, t.franchID, c.year
ORDER BY c.year;