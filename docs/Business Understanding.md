# Business Understanding

## Requirement of Analysis

### Hockey

#### Domain

##### Ice Hockey Game
- Game in a Ice rink between two teams
- Each Team has Six Player on the ice at a time, including the goaltender
- A game lasts one hour of gampeplay
- The team that scores the mosst goals wins; ties are resolved in overtime or shootout

##### Hockey Season

- Teams compete in a regular season divided into Eastern and Western conferences, each of which is further split into divisions. Teams accumulate points to reach the best possible standing
- At the end of the regular season, a fixed number of top performing teams qualify for the postseason playoffs where they compete in elimination series to win the championship throphy

##### League structure (as in the last seasons of the data, 2009/10)

30 teams → 2 conferences of 15 → 3 divisions of 5 per conference. Divisions are geographic.

| Conference | Division | Teams (2009/10) |
|---|---|---|
| Eastern | Atlantic (AT) | New Jersey, Pittsburgh, Philadelphia, NY Rangers, NY Islanders |
| Eastern | Northeast (NE) | Boston, Buffalo, Ottawa, Montreal, Toronto |
| Eastern | Southeast (SE) | Washington, Carolina, Atlanta, Florida, Tampa Bay |
| Western | Central (CE) | Chicago, Detroit, St. Louis, Nashville, Columbus |
| Western | Northwest (NW) | Vancouver, Calgary, Minnesota, Colorado, Edmonton |
| Western | Pacific (PC) | San Jose, Phoenix, Los Angeles, Anaheim, Dallas |

##### Regular-season schedule (82 games per team)

Every team plays every other team, but not the same number of times. Verified in `TeamVsTeam` for 2009:

| Opponent | Number of opponents | Games vs each | Total |
|---|---|---|---|
| Same division | 4 | 6 | 24 |
| Same conference, other division | 10 | 4 | 40 |
| Other conference | 15 | 1 (2 vs 3 of them, by rotation) | 18 |
| | | | **82** |

- About 78% of the games (64 of 82) are inside the conference, and 24 are against division rivals → the strength of a team's division affects its points (strength of schedule).
- This format holds from 2008/09 to 2010/11. Earlier seasons had even fewer inter-conference games, and in some seasons not every pair of teams met.

##### Points and standings

| Result | Points |
|---|---|
| Win (regulation, overtime or shootout) | 2 |
| Overtime / shootout loss (OTL) | 1 |
| Tie (only until 2003/04) | 1 |
| Regulation loss | 0 |

- Pts = 2·W + T + OTL. Since 2005/06 there are no ties: 5 minutes of overtime, then a shootout.
- Seasons have different lengths (84 games in 1992–94, 48 in the 1994/95 lockout, 82 otherwise), so we compare teams with **points% = Pts / (2·G)**.
- Three standings exist at the same time, all sorted by points: division (5 teams; the `rank` column of `Teams`), conference (15 teams; decides the playoffs) and league (30 teams; the best wins the Presidents' Trophy).
- Tie-break on equal points: more wins first (the official rule then uses head-to-head and goal differential).
- **Conference standing:** the 3 division winners take places 1–3 of the conference, even with fewer points than other teams; the other 12 teams follow by points from 4th place.

##### Playoffs

- The top 8 of each conference qualify (16 teams).
- Round 1 inside each conference: 1st vs 8th, 2nd vs 7th, 3rd vs 6th, 4th vs 5th. The following rounds are also inside the conference.
- The two conference champions play the Stanley Cup final. Every series is best of 7 (first to 4 wins).

##### Implications for the project / pending work

- [ ] **Division-winner rule not applied yet.** The model sorts teams only by predicted points%. The 2010 predictions (notebook 04) and the conference ranking in `ranking_metrics` (`src/validation.py`) should put the predicted division winners in places 1–3. This hardly changes who makes the playoffs, but it changes the order inside the top 8 (e.g. 2010: Pittsburgh 97 pts would drop below Boston 91 pts, the Northeast winner). After the change, update slides 13 and 24 of the deck.
- [ ] **Possible feature: strength of schedule**, e.g. the mean points% at t-1 of the 4 division rivals (24 of the 82 games).

### Requirements

Using the provided historical data, predict for the target season:

- a) The final regular season ranking of the teams
- b) The set of teams that will change choaches. Following the teacher's clarification, a choaching change is considered during the season, i.e whether the team changes coach during the current season
- c) A third requirement still to be announced. The solution should be flexible and modular enough to accommodate it with little rework

### End Users and Objectives

|**Requirements** | **End Users**| **How they would use the prediction**| 
| --------- | ----------- |------------ |
| a) Final Ranking | Scouts, bettors, analysts, media| Scouting and roster planning, betting decisions, forecasting which teams reach the playoffs|
| b) Coach Change | Team Management, media, contract and staffing planning| Management decisions, contract planning, anticipating the coaching market, media coverage|

### What each user needs from the output

- a) A complete ranking of all teams. Users benefit from knowing which teams are likely to land near the playoff cut-off
- b) A list of teams predicted to change coach. A probability or risk score per team.

### Constraints and Assumptions

- **Prediction Time:** predictions are made the day before the first game of the new season. Only information available at that moment may be used
- **Data:** only the historical data provided in the assigment is used
- **Coaching change timing:** considered at the end of the season, as confirmed by the teacher

### Expectations on Quality

- a) The predicted ranking should be close to the real final standings, and especially reliable at separating playoff teams from non-playoff teams.
- b) The model should identify most of the teams that change coach without producing too many false alarms

## Business Goals

|Business Goals|
| ------------ |
| I want to know before the season starts, how teams will finish? |
| Will the team make the playoffs? |
| I want to know what teams will change coach? |



## Translation of business goals into data mining goals

| Business Goals | Data Mining Goals| Type |
| -------------- | ---------------- | ---- |
| I want to know before the season starts, how teams will finish? | Predict each team's points percentage Pts / (2·G) for season t, then sort the teams (within division and league) | Regression then ranking |
| Will the team make the playoffs? | Predict playoff yes/no | Binary Classification |
| I want to know what teams will change coach? | Predict whether the team has a coach change in season | Binary Classification |
