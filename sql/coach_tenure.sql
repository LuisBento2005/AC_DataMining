--one row per coach, franchise and season in which the coach led that franchise
SELECT c.coachID, c.year, c.lgID,
t.franchID
FROM Coaches c
JOIN Teams t ON t.year = c.year AND t.tmID = c.tmID AND t.lgID = c.lgID
GROUP BY c.coachID, t.franchID, c.year
ORDER BY c.year;