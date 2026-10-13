# Requirements of analysis

## Hockey

### Domain

#### Ice Hockey Game
- Game in a Ice rink between two teams
- Each Team has Six Player on the ice at a time, including the goaltender
- A game lasts one hour of gampeplay
- The team that scores the mosst goals wins; ties are resolved in overtime or shootout

#### Hockey Season

- Teams compete in a regular season divided into Eastern and Western conferences, each of which is further split into divisions. Teams accumulate points to reach the best possible standing
- At the end of the regular season, a fixed number of top performing teams qualify for the postseason playoffs where they compete in elimination series to win the championship throphy

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

##### What each user needs from the output

- a) A complete ranking of all teams. Users benefit from knowing which teams are likely to land near the playoff cut-off
- b) A list of teams predicted to change coach. A probability or risk score per team.

### Constraints and Assumptions

- **Prediction Time:** predictions are made the day before the first game of the new season. Only information available at that moment may be used
- **Data:** only the historical data provided in the assigment is used
- **Coaching change timing:** considered at the end of the season, as confirmed by the teacher

### Expectations on Quality

- a) The predicted ranking should be close to the real final standings, and especially reliable at separating playoff teams from non-playoff teams.
- b) The model should identify most of the teams that change coach without producing too many false alarms

