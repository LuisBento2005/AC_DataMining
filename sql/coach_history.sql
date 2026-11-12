-- One row per coach per season (all leagues): the coach's totals for that season,

SELECT c.coachID, c.year, c.lgID,
       COUNT(*)                   AS n_stints,
       SUM(c.g)                   AS g,
       SUM(c.w)                   AS w,
       SUM(c.l)                   AS l,
       SUM(c.t)                   AS t,
       COALESCE(SUM(c.postg), 0)  AS postg
FROM Coaches c
GROUP BY c.coachID, c.year, c.lgID
ORDER BY c.coachID, c.year;
