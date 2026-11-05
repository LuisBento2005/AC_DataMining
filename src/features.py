"""Build the modelling dataset: one row per (franchise, season) with leak-free features.

Rule: every feature of season t uses only information available the day before
season t starts, i.e. statistics of seasons t-1, t-2, ... plus facts known at that
moment (the coach who opens the season, the division the team plays in).

Usage:
    from features import build_dataset
    df = build_dataset()                 # all NHL seasons + one future season (2010)
    df = build_dataset(roster_known=True) # also the optional season-t roster features
"""
from pathlib import Path
import sqlite3

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "data" / "hockey.db"
SQL = ROOT / "sql"

# Season statistics that are turned into "_lag1" features (value of the previous season).
LAG_COLS = [
    "pts_pct", "win_pct", "gf_pg", "ga_pg", "gd_pg", "pyth_pct", "luck", "pim_pg",
    "pp_pct", "pk_pct", "pp_opp_pg", "sh_diff_pg", "home_win_pct", "road_win_pct",
    "late_win_pct", "late_form", "made_playoffs", "playoff_depth", "div_rank",
    # roster of the previous season
    "n_players", "roster_pts_pg", "top_scorer_pts", "n_20goal", "n_60pts", "avg_age",
    "avg_weight", "n_award_winners",
    # goaltending of the previous season
    "team_sv_pct", "main_goalie_sv_pct", "main_goalie_share",
]
ROSTER_KNOWN_COLS = ["rk_prev_pts", "rk_n20goal", "rk_share_rookies", "rk_share_returning"]


def connect():
    if not DB.exists():
        raise FileNotFoundError(f"{DB} not found. Run: python src/load_db.py")
    return sqlite3.connect(DB)


def run_sql(con, name):
    """Run sql/<name>.sql and return a DataFrame."""
    return pd.read_sql((SQL / f"{name}.sql").read_text(), con)


def read_checks(con, name="data_quality"):
    """Run every '-- @check <name>' block of a SQL file. Returns {check_name: DataFrame}."""
    text = (SQL / f"{name}.sql").read_text()
    out = {}
    for block in text.split("-- @check ")[1:]:
        header, _, body = block.partition("\n")
        if not body.strip() or ":" not in header:
            continue
        out[header.split(":")[0].strip()] = pd.read_sql(body.strip().rstrip(";"), con)
    return out


# ---------------------------------------------------------------------------
# Coaches
# ---------------------------------------------------------------------------
def _coach_features(con, coach_season):
    """Features of the coach who opens each franchise-season, using only earlier seasons."""
    coaches = pd.read_sql("SELECT coachID, year, tmID, lgID, stint, g, w, l, t FROM Coaches", con)
    awards = pd.read_sql("SELECT coachID, year FROM AwardsCoaches", con)
    master = pd.read_sql(
        "SELECT coachID, playerID, hofID, birthYear FROM Master WHERE coachID IS NOT NULL", con
    ).drop_duplicates("coachID")
    hof = pd.read_sql("SELECT hofID, year AS hof_year, category FROM HOF", con)
    master = master.merge(hof, on="hofID", how="left")

    # Was the coach replaced by someone else during a season? (he was not the last coach)
    last_stint = coaches.groupby(["year", "tmID", "lgID"])["stint"].transform("max")
    coaches["was_replaced"] = (coaches["stint"] < last_stint).astype(int)

    # Set of coaches per franchise-season, to compute tenure.
    by_fy = {}
    for fr, yr, c in pd.read_sql(
        "SELECT t.franchID, c.year, c.coachID FROM Coaches c JOIN Teams t "
        "ON t.year=c.year AND t.tmID=c.tmID AND t.lgID=c.lgID WHERE c.lgID='NHL'", con
    ).itertuples(index=False):
        by_fy.setdefault((fr, yr), set()).add(c)

    years_of = coach_season.groupby("franchID")["year"].apply(sorted).to_dict()

    rows = []
    for r in coach_season.itertuples(index=False):
        cid, fr, yr = r.coach, r.franchID, r.year
        past = coaches[(coaches.coachID == cid) & (coaches.year < yr)]
        # tenure: consecutive previous franchise seasons coached by the same person
        tenure = 0
        prev_years = [y for y in years_of.get(fr, []) if y < yr]
        for y in reversed(prev_years):
            if cid in by_fy.get((fr, y), set()):
                tenure += 1
            else:
                break
        m = master[master.coachID == cid]
        birth = m.birthYear.iloc[0] if len(m) else np.nan
        hof_player = (
            int(len(m) and pd.notna(m.hof_year.iloc[0]) and m.hof_year.iloc[0] < yr
                and m.category.iloc[0] == "Player")
        )
        g, w = past.g.sum(), past.w.sum()
        rows.append({
            "franchID": fr, "year": yr,
            "coach_tenure": tenure,
            "coach_career_g": g,
            "coach_career_win_pct": w / g if g > 0 else np.nan,
            "coach_n_seasons": past.year.nunique(),
            "coach_n_teams": past.tmID.nunique(),
            "coach_times_replaced": past.was_replaced.sum(),
            "coach_awards": int((awards[(awards.coachID == cid) & (awards.year < yr)]).shape[0]),
            "coach_former_player": int(len(m) > 0 and pd.notna(m.playerID.iloc[0])),
            "coach_hof_player": hof_player,
            "coach_age": yr - birth if pd.notna(birth) else np.nan,
            "coach_rookie": int(g == 0),
        })
    return pd.DataFrame(rows)


# ---------------------------------------------------------------------------
# Main builder
# ---------------------------------------------------------------------------
def build_dataset(roster_known=False, add_future=True):
    con = connect()
    team = run_sql(con, "team_season")
    roster = run_sql(con, "roster_season")
    goalie = run_sql(con, "goalie_season")
    coach = run_sql(con, "coach_season")

    team["luck"] = team["pts_pct"] - team["pyth_pct"]          # points above "deserved"
    team["late_form"] = team["late_win_pct"] - team["win_pct"]  # finished stronger than average?

    df = (team.merge(roster, on=["franchID", "year"], how="left")
              .merge(goalie, on=["franchID", "year"], how="left")
              .merge(coach, on=["franchID", "year"], how="left"))
    df["roster_pts_pg"] = df["roster_pts"] / df["G"]

    # league-wide rank by points% (1 = best) and conference rank, the "actual" rankings
    df["league_rank"] = df.groupby("year")["pts_pct"].rank(ascending=False, method="min")
    df["conf_rank"] = df.groupby(["year", "confID"])["pts_pct"].rank(ascending=False, method="min")

    df = df.sort_values(["franchID", "year"]).reset_index(drop=True)

    # ---- future season (the one we must predict): copy each active franchise of the last year
    last = df.year.max()
    if add_future:
        fut = df[df.year == last][["franchID", "tmID", "name", "confID", "divID", "last_coach"]].copy()
        fut["year"] = last + 1
        fut["first_coach"] = fut["last_coach"]   # assumption: the coach who ended 2009 opens 2010
        fut["last_coach"] = np.nan
        df = pd.concat([df, fut], ignore_index=True).sort_values(["franchID", "year"]).reset_index(drop=True)
    df["is_future"] = (df.year > last).astype(int)

    g = df.groupby("franchID")

    # ---- targets ------------------------------------------------------------
    # (b) three possible definitions of "the team changes coach in season t"
    df["coach_change_during"] = df["changed_during"]
    next_first = g["first_coach"].shift(-1)
    df["coach_change_end"] = np.where(next_first.isna(), np.nan,
                                      (df["last_coach"] != next_first).astype(float))
    df["coach_change_any"] = np.where(
        df["coach_change_during"] == 1, 1.0, df["coach_change_end"])
    for c in ["coach_change_during", "coach_change_end", "coach_change_any"]:
        df.loc[df.is_future == 1, c] = np.nan

    # ---- lag features (season t-1, t-2 of the same franchise) ---------------
    for c in LAG_COLS:
        df[f"{c}_lag1"] = g[c].shift(1)
    df["pts_pct_lag2"] = g["pts_pct"].shift(2)
    df["pts_pct_ma3"] = g["pts_pct"].transform(lambda s: s.shift(1).rolling(3, min_periods=1).mean())
    df["gd_pg_ma3"] = g["gd_pg"].transform(lambda s: s.shift(1).rolling(3, min_periods=1).mean())
    df["pts_trend"] = df["pts_pct_lag1"] - df["pts_pct_lag2"]
    df["playoff_streak_miss"] = g["made_playoffs"].transform(_miss_streak)
    df["seasons_in_league"] = g.cumcount()
    df["is_new_team"] = df["pts_pct_lag1"].isna().astype(int)

    # ---- coach facts known before the season --------------------------------
    df["coach"] = df["first_coach"]
    prev_last = g["last_coach"].shift(1)
    df["new_coach"] = np.where(prev_last.isna(), 0, (df["first_coach"] != prev_last).astype(int))
    df["changed_during_lag1"] = g["changed_during"].shift(1)
    # coaching instability of the franchise: number of distinct coaches in t-5 .. t-1
    df["franchise_coaches_5y"] = _distinct_coaches_window(df, 5)

    cf = _coach_features(con, df[["franchID", "year", "coach"]].dropna(subset=["coach"]))
    df = df.merge(cf, on=["franchID", "year"], how="left")
    # interaction found in the EDA: long-tenured coach with a bad team
    df["tenure_x_badness"] = df["coach_tenure"] * (0.5 - df["pts_pct_lag1"])

    # ---- domain prior for expansion teams (no previous season) --------------
    # Lag features of a new team are filled with the mean first-season points% of the
    # expansion teams that came BEFORE season t (only the past is used).
    first_seasons = df[(df.seasons_in_league == 0) & df.pts_pct.notna()][["year", "pts_pct"]]
    for i in df.index[df.is_new_team == 1]:
        yr = df.at[i, "year"]
        prior = first_seasons[first_seasons.year < yr].pts_pct.mean()
        for c in ["pts_pct_lag1", "pts_pct_lag2", "pts_pct_ma3"]:
            df.at[i, c] = prior

    if roster_known:
        rk = run_sql(con, "roster_known")
        df = df.merge(rk, on=["franchID", "year"], how="left")
    con.close()
    return df.sort_values(["year", "franchID"]).reset_index(drop=True)


def _miss_streak(s):
    """Consecutive seasons without playoffs up to t-1."""
    out, streak = [], 0
    for v in s:
        out.append(streak)
        if pd.isna(v):
            continue
        streak = streak + 1 if v == 0 else 0
    return pd.Series(out, index=s.index)


def _distinct_coaches_window(df, k):
    res = pd.Series(np.nan, index=df.index)
    for fr, grp in df.groupby("franchID"):
        coaches = list(zip(grp.index, grp.first_coach, grp.last_coach))
        for j, (idx, _, _) in enumerate(coaches):
            window = coaches[max(0, j - k):j]
            names = {c for _, a, b in window for c in (a, b) if isinstance(c, str)}
            res[idx] = len(names)
    return res


# ---------------------------------------------------------------------------
# Feature groups (used by the notebooks)
# ---------------------------------------------------------------------------
TEAM_FEATURES = [
    "pts_pct_lag1", "pts_pct_lag2", "pts_pct_ma3", "pts_trend", "win_pct_lag1",
    "gf_pg_lag1", "ga_pg_lag1", "gd_pg_lag1", "gd_pg_ma3", "pyth_pct_lag1", "luck_lag1",
    "pim_pg_lag1", "pp_pct_lag1", "pk_pct_lag1", "pp_opp_pg_lag1", "sh_diff_pg_lag1",
    "home_win_pct_lag1", "road_win_pct_lag1", "late_win_pct_lag1", "late_form_lag1",
    "made_playoffs_lag1", "playoff_depth_lag1", "div_rank_lag1", "playoff_streak_miss",
    "seasons_in_league", "is_new_team",
]
ROSTER_FEATURES = [
    "n_players_lag1", "roster_pts_pg_lag1", "top_scorer_pts_lag1", "n_20goal_lag1",
    "n_60pts_lag1", "avg_age_lag1", "avg_weight_lag1", "n_award_winners_lag1",
    "team_sv_pct_lag1", "main_goalie_sv_pct_lag1", "main_goalie_share_lag1",
]
COACH_FEATURES = [
    "new_coach", "changed_during_lag1", "franchise_coaches_5y", "coach_tenure",
    "coach_career_g", "coach_career_win_pct", "coach_n_seasons", "coach_n_teams",
    "coach_times_replaced", "coach_awards", "coach_former_player", "coach_hof_player",
    "coach_age", "coach_rookie", "tenure_x_badness",
]
ALL_FEATURES = TEAM_FEATURES + ROSTER_FEATURES + COACH_FEATURES
