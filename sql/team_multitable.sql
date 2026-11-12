-- Master multi-table SQLite query for Data Understanding & Feature Exploration (NHL 1982–2009, 690 rows).
-- Integrates 9 tables: Teams, Goalies, TeamSplits, Scoring, Master, AwardsPlayers, TeamsPost, Coaches, AwardsCoaches.
-- Computes:
--   1. Same-season (s) multi-domain statistics (offense, defense, special teams, goaltending, shot share, PDO, splits, roster, playoffs, division strength)
--   2. Season-centered (_rel) metrics via AVG(...) OVER (PARTITION BY year) to remove era / OTL point inflation
--   3. Lagged (t-1, _prev) metrics via LAG(...) OVER (PARTITION BY franchID ORDER BY year), handling the 2004 lockout (2005 lags from 2003)
--   4. Opening coach profile, career history before season t, franchise tenure before season t, and coach change flags (changed_during & changed_between)

WITH
-- 1. Goaltending per team-season
goalies_agg AS (
    SELECT
        g.year, g.lgID, g.tmID,
        COUNT(DISTINCT g.playerID)                       AS n_goalies_used,
        MAX(g.Min) * 1.0 / NULLIF(SUM(g.Min), 0)         AS starter_min_share,
        SUM(g.GA)                                        AS goalie_ga,
        SUM(g.SA)                                        AS goalie_sa,
        1.0 - SUM(g.GA) * 1.0 / NULLIF(SUM(g.SA), 0)     AS save_pct,
        SUM(COALESCE(g.SHO, 0))                          AS goalie_shutouts
    FROM Goalies g
    WHERE g.lgID = 'NHL' AND g.year >= 1979
    GROUP BY g.year, g.lgID, g.tmID
),
-- 2. Home/Road and Early/Late splits per team-season
splits_agg AS (
    SELECT
        ts.year, ts.lgID, ts.tmID,
        (2 * COALESCE(ts.hW, 0) + COALESCE(ts.hT, 0) + COALESCE(ts.hOTL, 0)) * 1.0
        / NULLIF(2 * (COALESCE(ts.hW, 0) + COALESCE(ts.hL, 0) + COALESCE(ts.hT, 0) + COALESCE(ts.hOTL, 0)), 0) AS home_pts_pct,
        (2 * COALESCE(ts.rW, 0) + COALESCE(ts.rT, 0) + COALESCE(ts.rOTL, 0)) * 1.0
        / NULLIF(2 * (COALESCE(ts.rW, 0) + COALESCE(ts.rL, 0) + COALESCE(ts.rT, 0) + COALESCE(ts.rOTL, 0)), 0) AS road_pts_pct,
        (2*(COALESCE(ts.SepW,0)+COALESCE(ts.OctW,0)+COALESCE(ts.NovW,0)+COALESCE(ts.DecW,0)+COALESCE(ts.JanW,0)) + COALESCE(ts.SepT,0)+COALESCE(ts.OctT,0)+COALESCE(ts.NovT,0)+COALESCE(ts.DecT,0)+COALESCE(ts.JanT,0) + COALESCE(ts.SepOL,0)+COALESCE(ts.OctOL,0)+COALESCE(ts.NovOL,0)+COALESCE(ts.DecOL,0)+COALESCE(ts.JanOL,0)) * 1.0
        / NULLIF(2*(COALESCE(ts.SepW,0)+COALESCE(ts.OctW,0)+COALESCE(ts.NovW,0)+COALESCE(ts.DecW,0)+COALESCE(ts.JanW,0)+COALESCE(ts.SepL,0)+COALESCE(ts.OctL,0)+COALESCE(ts.NovL,0)+COALESCE(ts.DecL,0)+COALESCE(ts.JanL,0)+COALESCE(ts.SepT,0)+COALESCE(ts.OctT,0)+COALESCE(ts.NovT,0)+COALESCE(ts.DecT,0)+COALESCE(ts.JanT,0)+COALESCE(ts.SepOL,0)+COALESCE(ts.OctOL,0)+COALESCE(ts.NovOL,0)+COALESCE(ts.DecOL,0)+COALESCE(ts.JanOL,0)), 0) AS early_pts_pct,
        (2*(COALESCE(ts.FebW,0)+COALESCE(ts.MarW,0)+COALESCE(ts.AprW,0)) + COALESCE(ts.FebT,0)+COALESCE(ts.MarT,0)+COALESCE(ts.AprT,0) + COALESCE(ts.FebOL,0)+COALESCE(ts.MarOL,0)+COALESCE(ts.AprOL,0)) * 1.0
        / NULLIF(2*(COALESCE(ts.FebW,0)+COALESCE(ts.MarW,0)+COALESCE(ts.AprW,0)+COALESCE(ts.FebL,0)+COALESCE(ts.MarL,0)+COALESCE(ts.AprL,0)+COALESCE(ts.FebT,0)+COALESCE(ts.MarT,0)+COALESCE(ts.AprT,0)+COALESCE(ts.FebOL,0)+COALESCE(ts.MarOL,0)+COALESCE(ts.AprOL,0)), 0) AS late_pts_pct
    FROM TeamSplits ts
    WHERE ts.lgID = 'NHL' AND ts.year >= 1979
),
-- 3. Roster aggregations (age, experience, shooting%, top-3 concentration, 20G scorers, retention, awards)
player_team AS (
    SELECT
        s.year, s.lgID, s.tmID, t.franchID, s.playerID,
        SUM(COALESCE(s.GP, 0))  AS gp,
        SUM(COALESCE(s.G, 0))   AS g,
        SUM(COALESCE(s.Pts, 0)) AS pts,
        SUM(COALESCE(s.SOG, 0)) AS sog
    FROM Scoring s
    JOIN Teams t ON s.year = t.year AND s.lgID = t.lgID AND s.tmID = t.tmID
    WHERE s.lgID = 'NHL' AND s.year >= 1978 AND COALESCE(s.GP, 0) > 0
    GROUP BY s.year, s.lgID, s.tmID, t.franchID, s.playerID
),
ranked_players AS (
    SELECT
        cur.*,
        m.birthYear,
        m.firstNHL,
        ROW_NUMBER() OVER (PARTITION BY cur.year, cur.tmID ORDER BY cur.g DESC, cur.pts DESC, cur.playerID) AS goal_rank,
        SUM(cur.g) OVER (PARTITION BY cur.year, cur.tmID)                                                   AS team_player_g,
        CASE WHEN prev.playerID IS NOT NULL THEN 1 ELSE 0 END                                               AS is_returning
    FROM player_team cur
    LEFT JOIN Master m ON cur.playerID = m.playerID
    LEFT JOIN player_team prev
        ON cur.franchID = prev.franchID
       AND cur.playerID = prev.playerID
       AND (cur.year - prev.year = 1 OR (cur.year = 2005 AND prev.year = 2003))
    WHERE cur.year >= 1979
),
player_awards_agg AS (
    SELECT year, lgID, playerID, COUNT(*) AS n_awards
    FROM AwardsPlayers WHERE lgID = 'NHL'
    GROUP BY year, lgID, playerID
),
roster_agg AS (
    SELECT
        r.year, r.lgID, r.tmID,
        COUNT(DISTINCT r.playerID)                                                                   AS roster_size,
        SUM(r.gp * (r.year - r.birthYear)) * 1.0 / NULLIF(SUM(CASE WHEN r.birthYear IS NOT NULL THEN r.gp END), 0) AS weighted_age,
        SUM(r.gp * (r.year - r.firstNHL))  * 1.0 / NULLIF(SUM(CASE WHEN r.firstNHL  IS NOT NULL THEN r.gp END), 0) AS weighted_exp,
        SUM(r.g) * 1.0 / NULLIF(SUM(r.sog), 0)                                                       AS shooting_pct,
        SUM(r.sog)                                                                                   AS roster_sog,
        SUM(CASE WHEN r.goal_rank <= 3 THEN r.g ELSE 0 END) * 1.0 / NULLIF(MAX(r.team_player_g), 0)  AS top3_goal_share,
        SUM(CASE WHEN r.g >= 20 THEN 1 ELSE 0 END)                                                   AS n_20g_scorers,
        SUM(CASE WHEN r.is_returning = 1 THEN r.pts ELSE 0 END) * 1.0 / NULLIF(SUM(r.pts), 0)        AS returning_pts_share,
        SUM(CASE WHEN r.is_returning = 1 THEN r.gp  ELSE 0 END) * 1.0 / NULLIF(SUM(r.gp), 0)         AS returning_gp_share,
        COALESCE(SUM(aw.n_awards), 0)                                                                AS player_awards
    FROM ranked_players r
    LEFT JOIN player_awards_agg aw ON r.year = aw.year AND r.lgID = aw.lgID AND r.playerID = aw.playerID
    GROUP BY r.year, r.lgID, r.tmID
),
-- 4. Coach career & tenure before season t, plus coach change flags (changed_during & changed_between)
coach_season_totals AS (
    SELECT
        c.coachID, c.year,
        SUM(c.g) AS g, SUM(c.w) AS w, SUM(c.l) AS l, SUM(c.t) AS t,
        COALESCE(SUM(c.postg), 0) AS postg
    FROM Coaches c
    GROUP BY c.coachID, c.year
),
coach_awards_yr AS (
    SELECT coachID, year, COUNT(award) AS awards_won
    FROM AwardsCoaches
    GROUP BY coachID, year
),
coach_career AS (
    SELECT
        cs.coachID, cs.year,
        COALESCE(SUM(cs.g)     OVER w_c - cs.g, 0)     AS games_before,
        COALESCE(SUM(cs.w)     OVER w_c - cs.w, 0)     AS wins_before,
        COALESCE(SUM(cs.t)     OVER w_c - cs.t, 0)     AS ties_before,
        COALESCE(SUM(cs.l)     OVER w_c - cs.l, 0)     AS losses_before,
        COALESCE(SUM(cs.postg) OVER w_c - cs.postg, 0) AS postgames_before,
        COUNT(*)               OVER w_c - 1            AS seasons_before,
        COALESCE(SUM(COALESCE(ca.awards_won, 0)) OVER w_c - COALESCE(ca.awards_won, 0), 0) AS awards_before
    FROM coach_season_totals cs
    LEFT JOIN coach_awards_yr ca ON cs.coachID = ca.coachID AND cs.year = ca.year
    WINDOW w_c AS (PARTITION BY cs.coachID ORDER BY cs.year ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
),
coach_franch_years AS (
    SELECT DISTINCT c.coachID, t.franchID, c.year,
           CASE WHEN c.year > 2004 THEN c.year - 1 ELSE c.year END AS seq_yr
    FROM Coaches c
    JOIN Teams t ON c.year = t.year AND c.tmID = t.tmID AND c.lgID = t.lgID
),
coach_franch_streaks AS (
    SELECT
        coachID, franchID, year, seq_yr,
        seq_yr - ROW_NUMBER() OVER (PARTITION BY coachID, franchID ORDER BY seq_yr) AS streak_grp
    FROM coach_franch_years
),
coach_tenure AS (
    SELECT
        coachID, franchID, year,
        ROW_NUMBER() OVER (PARTITION BY coachID, franchID, streak_grp ORDER BY seq_yr) - 1 AS tenure_before
    FROM coach_franch_streaks
),
coaches_ordered AS (
    SELECT
        t.franchID, c.year, c.tmID, c.coachID, c.stint, c.g,
        ROW_NUMBER() OVER (PARTITION BY t.franchID, c.year ORDER BY c.stint ASC,  c.g DESC, c.coachID) AS rn_first,
        ROW_NUMBER() OVER (PARTITION BY t.franchID, c.year ORDER BY c.stint DESC, c.g DESC, c.coachID) AS rn_last
    FROM Coaches c
    JOIN Teams t ON t.year = c.year AND t.tmID = c.tmID AND t.lgID = c.lgID
    WHERE c.lgID = 'NHL'
),
team_coach_flags AS (
    SELECT
        franchID, year,
        COUNT(DISTINCT coachID)                      AS n_coaches,
        MAX(stint)                                   AS n_stints,
        MAX(CASE WHEN rn_first = 1 THEN coachID END) AS first_coach,
        MAX(CASE WHEN rn_last  = 1 THEN coachID END) AS last_coach
    FROM coaches_ordered
    GROUP BY franchID, year
),
team_coach_with_prev AS (
    SELECT
        tc.*,
        LAG(tc.year)       OVER (PARTITION BY tc.franchID ORDER BY tc.year) AS prev_coach_year,
        LAG(tc.last_coach) OVER (PARTITION BY tc.franchID ORDER BY tc.year) AS prev_last_coach,
        CASE WHEN tc.n_stints > 1 THEN 1 ELSE 0 END                         AS changed_during
    FROM team_coach_flags tc
),
-- 5. Combine all per-season team, goalie, split, roster, playoff & coach data
season_combined AS (
    SELECT
        t.year, t.lgID, t.tmID, t.franchID, t.name, t.confID, t.divID, t.rank, t.playoff, t.G,
        -- Core team performance
        t.Pts * 1.0 / (2 * t.G)                                             AS pts_pct,
        (t.Pts * 1.0 / (2 * t.G)) - AVG(t.Pts * 1.0 / (2 * t.G)) OVER (PARTITION BY t.year) AS pts_pct_rel,
        t.GF * 1.0 / t.G                                                    AS gf_pg,
        t.GA * 1.0 / t.G                                                    AS ga_pg,
        (t.GF - t.GA) * 1.0 / t.G                                           AS gd_pg,
        (t.GF * t.GF * 1.0) / NULLIF(t.GF * t.GF + t.GA * t.GA, 0)          AS pyth_pct,
        (t.Pts * 1.0 / (2 * t.G)) - ((t.GF * t.GF * 1.0) / NULLIF(t.GF * t.GF + t.GA * t.GA, 0)) AS luck,
        t.PIM * 1.0 / t.G                                                   AS pim_pg,
        t.PPG * 1.0 / NULLIF(t.PPC, 0)                                      AS pp_pct,
        1.0 - t.PKG * 1.0 / NULLIF(t.PKC, 0)                                AS pk_pct,
        t.PPC * 1.0 / t.G                                                   AS pp_opp_pg,
        t.SHF * 1.0 / t.G                                                   AS shf_pg,
        -- Playoff ordinal & workload
        CASE WHEN t.playoff IS NULL THEN 0 ELSE 1 END                       AS made_playoffs,
        CASE
            WHEN t.playoff IS NULL THEN 0
            WHEN t.playoff IN ('PRE', 'DF', 'DSF', 'CQF') THEN 1
            WHEN t.playoff IN ('QF', 'CSF') THEN 2
            WHEN t.playoff IN ('SF', 'CF') THEN 3
            WHEN t.playoff = 'F' THEN 4
            WHEN t.playoff = 'SC' THEN 5
            ELSE 0
        END                                                                 AS playoff_round,
        COALESCE(tp.G, 0)                                                   AS post_games,
        -- Goalies
        ga.save_pct,
        ga.save_pct - AVG(ga.save_pct) OVER (PARTITION BY t.year)           AS save_pct_rel,
        ga.goalie_sa * 1.0 / t.G                                            AS sa_pg,
        ga.starter_min_share,
        ga.goalie_shutouts * 1.0 / t.G                                      AS shutouts_pg,
        -- Roster & Shot metrics
        ra.weighted_age,
        ra.weighted_exp,
        ra.shooting_pct,
        ra.shooting_pct - AVG(ra.shooting_pct) OVER (PARTITION BY t.year)   AS shooting_pct_rel,
        ra.roster_sog * 1.0 / t.G                                           AS sog_pg,
        ra.roster_sog * 1.0 / NULLIF(ra.roster_sog + ga.goalie_sa, 0)       AS shot_share,
        ga.save_pct + ra.shooting_pct                                       AS pdo,
        (ga.save_pct + ra.shooting_pct) - AVG(ga.save_pct + ra.shooting_pct) OVER (PARTITION BY t.year) AS pdo_rel,
        ra.top3_goal_share,
        ra.n_20g_scorers,
        ra.returning_pts_share,
        ra.returning_gp_share,
        ra.player_awards,
        -- Splits
        sp.home_pts_pct,
        sp.road_pts_pct,
        sp.home_pts_pct - sp.road_pts_pct                                   AS home_road_gap,
        sp.early_pts_pct,
        sp.late_pts_pct,
        sp.late_pts_pct - sp.early_pts_pct                                  AS late_surge,
        -- Coach targets & opening coach attributes
        tc.first_coach                                                      AS coachID,
        tc.changed_during,
        CASE WHEN tc.prev_coach_year IS NULL THEN NULL
             WHEN NOT (t.year - tc.prev_coach_year = 1 OR (t.year = 2005 AND tc.prev_coach_year = 2003)) THEN NULL
             WHEN tc.first_coach <> tc.prev_last_coach THEN 1 ELSE 0 END    AS changed_between,
        t.year - cm.birthYear                                               AS coach_age,
        CASE WHEN cm.playerID IS NOT NULL THEN 1 ELSE 0 END                 AS coach_former_player,
        CASE WHEN cm.firstNHL IS NOT NULL THEN 1 ELSE 0 END                 AS coach_former_nhl,
        cc.seasons_before                                                   AS coach_seasons_before,
        cc.games_before                                                     AS coach_games_before,
        (cc.wins_before + 0.5 * cc.ties_before) * 1.0 / NULLIF(cc.games_before, 0) AS coach_win_before_pct,
        CASE WHEN COALESCE(cc.games_before, 0) = 0 THEN 1 ELSE 0 END        AS is_rookie_coach,
        cc.awards_before                                                    AS coach_awards_before,
        ct.tenure_before
    FROM Teams t
    LEFT JOIN TeamsPost tp          ON t.year = tp.year AND t.lgID = tp.lgID AND t.tmID = tp.tmID
    LEFT JOIN goalies_agg ga        ON t.year = ga.year AND t.lgID = ga.lgID AND t.tmID = ga.tmID
    LEFT JOIN roster_agg ra         ON t.year = ra.year AND t.lgID = ra.lgID AND t.tmID = ra.tmID
    LEFT JOIN splits_agg sp         ON t.year = sp.year AND t.lgID = sp.lgID AND t.tmID = sp.tmID
    LEFT JOIN team_coach_with_prev tc ON t.franchID = tc.franchID AND t.year = tc.year
    LEFT JOIN Master cm             ON tc.first_coach = cm.coachID
    LEFT JOIN coach_career cc       ON tc.first_coach = cc.coachID AND t.year = cc.year
    LEFT JOIN coach_tenure ct       ON tc.first_coach = ct.coachID AND t.franchID = ct.franchID AND t.year = ct.year
    WHERE t.lgID = 'NHL' AND t.year >= 1980
),
-- 6. Division rivals strength (computed on season_combined)
div_strength AS (
    SELECT
        a.year, a.franchID,
        AVG(b.pts_pct)     AS div_rivals_pts_pct,
        AVG(b.pts_pct_rel) AS div_rivals_pts_pct_rel,
        AVG(b.gd_pg)       AS div_rivals_gd_pg
    FROM season_combined a
    JOIN season_combined b
        ON a.year = b.year AND a.divID = b.divID AND a.franchID <> b.franchID
    GROUP BY a.year, a.franchID
),
-- 7. Attach lags (t-1) via window functions over franchID
with_lags AS (
    SELECT
        sc.*,
        ds.div_rivals_pts_pct,
        ds.div_rivals_pts_pct_rel,
        ds.div_rivals_gd_pg,
        LAG(sc.year) OVER w_f AS prev_year,
        LAG(sc.year, 2) OVER w_f AS prev2_year,
        -- Lagged performance & structure (valid only when consecutive season or 2003->2005)
        LAG(sc.pts_pct)             OVER w_f AS raw_pts_pct_prev,
        LAG(sc.pts_pct_rel)         OVER w_f AS raw_pts_pct_rel_prev,
        LAG(sc.pts_pct_rel, 2)      OVER w_f AS raw_pts_pct_rel_prev2,
        LAG(sc.gf_pg)               OVER w_f AS raw_gf_pg_prev,
        LAG(sc.ga_pg)               OVER w_f AS raw_ga_pg_prev,
        LAG(sc.gd_pg)               OVER w_f AS raw_gd_pg_prev,
        LAG(sc.pyth_pct)            OVER w_f AS raw_pyth_pct_prev,
        LAG(sc.luck)                OVER w_f AS raw_luck_prev,
        LAG(sc.pim_pg)              OVER w_f AS raw_pim_pg_prev,
        LAG(sc.pp_pct)              OVER w_f AS raw_pp_pct_prev,
        LAG(sc.pk_pct)              OVER w_f AS raw_pk_pct_prev,
        LAG(sc.pp_opp_pg)           OVER w_f AS raw_pp_opp_pg_prev,
        LAG(sc.shf_pg)              OVER w_f AS raw_shf_pg_prev,
        LAG(sc.made_playoffs)       OVER w_f AS raw_made_playoffs_prev,
        LAG(sc.playoff_round)       OVER w_f AS raw_playoff_round_prev,
        LAG(sc.post_games)          OVER w_f AS raw_post_games_prev,
        LAG(sc.save_pct)            OVER w_f AS raw_save_pct_prev,
        LAG(sc.save_pct_rel)        OVER w_f AS raw_save_pct_rel_prev,
        LAG(sc.sa_pg)               OVER w_f AS raw_sa_pg_prev,
        LAG(sc.starter_min_share)   OVER w_f AS raw_starter_min_share_prev,
        LAG(sc.shutouts_pg)         OVER w_f AS raw_shutouts_pg_prev,
        LAG(sc.weighted_age)        OVER w_f AS raw_weighted_age_prev,
        LAG(sc.weighted_exp)        OVER w_f AS raw_weighted_exp_prev,
        LAG(sc.shooting_pct)        OVER w_f AS raw_shooting_pct_prev,
        LAG(sc.shooting_pct_rel)    OVER w_f AS raw_shooting_pct_rel_prev,
        LAG(sc.sog_pg)              OVER w_f AS raw_sog_pg_prev,
        LAG(sc.shot_share)          OVER w_f AS raw_shot_share_prev,
        LAG(sc.pdo)                 OVER w_f AS raw_pdo_prev,
        LAG(sc.pdo_rel)             OVER w_f AS raw_pdo_rel_prev,
        LAG(sc.top3_goal_share)     OVER w_f AS raw_top3_goal_share_prev,
        LAG(sc.n_20g_scorers)       OVER w_f AS raw_n_20g_scorers_prev,
        LAG(sc.returning_pts_share) OVER w_f AS raw_returning_pts_share_prev,
        LAG(sc.returning_gp_share)  OVER w_f AS raw_returning_gp_share_prev,
        LAG(sc.player_awards)       OVER w_f AS raw_player_awards_prev,
        LAG(sc.home_pts_pct)        OVER w_f AS raw_home_pts_pct_prev,
        LAG(sc.road_pts_pct)        OVER w_f AS raw_road_pts_pct_prev,
        LAG(sc.home_road_gap)       OVER w_f AS raw_home_road_gap_prev,
        LAG(sc.early_pts_pct)       OVER w_f AS raw_early_pts_pct_prev,
        LAG(sc.late_pts_pct)        OVER w_f AS raw_late_pts_pct_prev,
        LAG(sc.late_surge)          OVER w_f AS raw_late_surge_prev,
        LAG(sc.changed_during)      OVER w_f AS raw_changed_during_prev,
        LAG(ds.div_rivals_pts_pct_rel) OVER w_f AS raw_div_rivals_pts_pct_rel_prev,
        -- Rolling 5-season franchise mid-season firings before season t
        COALESCE(SUM(sc.changed_during) OVER (PARTITION BY sc.franchID ORDER BY sc.year ROWS BETWEEN 5 PRECEDING AND 1 PRECEDING), 0) AS franch_changes_during_5y
    FROM season_combined sc
    LEFT JOIN div_strength ds ON sc.year = ds.year AND sc.franchID = ds.franchID
    WINDOW w_f AS (PARTITION BY sc.franchID ORDER BY sc.year)
)
SELECT
    year, lgID, tmID, franchID, name, confID, divID, rank, playoff, G,
    -- Same-season metrics
    pts_pct, pts_pct_rel, gf_pg, ga_pg, gd_pg, pyth_pct, luck,
    pim_pg, pp_pct, pk_pct, pp_opp_pg, shf_pg,
    made_playoffs, playoff_round, post_games,
    save_pct, save_pct_rel, sa_pg, starter_min_share, shutouts_pg,
    weighted_age, weighted_exp, shooting_pct, shooting_pct_rel, sog_pg, shot_share, pdo, pdo_rel,
    top3_goal_share, n_20g_scorers, returning_pts_share, returning_gp_share, player_awards,
    home_pts_pct, road_pts_pct, home_road_gap, early_pts_pct, late_pts_pct, late_surge,
    div_rivals_pts_pct, div_rivals_pts_pct_rel, div_rivals_gd_pg,
    -- Coach targets & opening coach attributes
    coachID, changed_during, changed_between,
    coach_age, coach_former_player, coach_former_nhl,
    coach_seasons_before, coach_games_before, coach_win_before_pct,
    is_rookie_coach, coach_awards_before, tenure_before,
    franch_changes_during_5y,
    -- Consecutive previous season indicator & lagged (t-1) features
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN prev_year ELSE NULL END AS prev_year,
    CASE WHEN prev_year IS NULL OR NOT (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN 1 ELSE 0 END AS is_expansion_team,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_pts_pct_prev END             AS pts_pct_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_pts_pct_rel_prev END         AS pts_pct_rel_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003))
          AND prev2_year IS NOT NULL AND (prev_year - prev2_year = 1 OR (prev_year = 2005 AND prev2_year = 2003))
         THEN raw_pts_pct_rel_prev - raw_pts_pct_rel_prev2 END                                                                             AS pts_pct_rel_trend,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_gf_pg_prev END               AS gf_pg_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_ga_pg_prev END               AS ga_pg_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_gd_pg_prev END               AS gd_pg_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_pyth_pct_prev END            AS pyth_pct_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_luck_prev END                AS luck_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_pim_pg_prev END              AS pim_pg_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_pp_pct_prev END              AS pp_pct_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_pk_pct_prev END              AS pk_pct_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_pp_opp_pg_prev END           AS pp_opp_pg_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_shf_pg_prev END              AS shf_pg_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_made_playoffs_prev END       AS made_playoffs_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_playoff_round_prev END       AS playoff_round_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_post_games_prev END          AS post_games_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_save_pct_prev END            AS save_pct_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_save_pct_rel_prev END        AS save_pct_rel_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_sa_pg_prev END               AS sa_pg_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_starter_min_share_prev END   AS starter_min_share_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_shutouts_pg_prev END         AS shutouts_pg_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_weighted_age_prev END        AS weighted_age_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_weighted_exp_prev END        AS weighted_exp_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_shooting_pct_prev END        AS shooting_pct_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_shooting_pct_rel_prev END    AS shooting_pct_rel_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_sog_pg_prev END              AS sog_pg_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_shot_share_prev END          AS shot_share_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_pdo_prev END                 AS pdo_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_pdo_rel_prev END             AS pdo_rel_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_top3_goal_share_prev END     AS top3_goal_share_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_n_20g_scorers_prev END       AS n_20g_scorers_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_returning_pts_share_prev END AS returning_pts_share_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_returning_gp_share_prev END  AS returning_gp_share_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_player_awards_prev END       AS player_awards_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_home_pts_pct_prev END        AS home_pts_pct_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_road_pts_pct_prev END        AS road_pts_pct_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_home_road_gap_prev END       AS home_road_gap_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_early_pts_pct_prev END       AS early_pts_pct_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_late_pts_pct_prev END        AS late_pts_pct_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_late_surge_prev END          AS late_surge_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_changed_during_prev END      AS changed_during_prev,
    CASE WHEN prev_year IS NOT NULL AND (year - prev_year = 1 OR (year = 2005 AND prev_year = 2003)) THEN raw_div_rivals_pts_pct_rel_prev END AS div_rivals_pts_pct_rel_prev
FROM with_lags
WHERE year >= 1982
ORDER BY year, franchID;
