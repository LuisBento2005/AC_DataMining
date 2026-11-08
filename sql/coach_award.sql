-- One row per coach-season in which the coach won at least one award, with the number of awards.

SELECT aw.coachID, aw.year,
       COUNT(aw.award) AS awards_won
FROM AwardsCoaches aw
GROUP BY aw.coachID, aw.year
ORDER BY aw.coachID, aw.year;
