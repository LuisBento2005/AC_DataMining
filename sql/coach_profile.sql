-- one row per coach stint, all leagues, with personal details from Master

SELECT Coaches.coachID, Coaches.year, Coaches.tmID, Coaches.lgID,
Coaches.stint, Master.birthYear, Master.birthMon, Master.birthDay, Master.playerID, Master.firstNHL
FROM Coaches
LEFT JOIN Master ON Coaches.coachID = Master.coachID