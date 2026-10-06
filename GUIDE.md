# Project Guide: Ice Hockey ML Project

This guide covers what we have to do in the project, how to do it, and which line of the grading rubric each part covers.

**Contents**

- [Part I: Overview](#part-i-overview)
- [Part II: Step-by-step guide (CRISP-DM)](#part-ii-step-by-step-guide-crisp-dm)
  - [Phase 0: Project management](#phase-0-project-management)
  - [Phase 1: Business Understanding](#phase-1-business-understanding)
  - [Phase 2: Data Understanding](#phase-2-data-understanding)
  - [Phase 3: Data Preparation](#phase-3-data-preparation)
  - [Phase 4: Modelling](#phase-4-modelling)
  - [Phase 5: Evaluation](#phase-5-evaluation)
  - [Phase 6: Presentation / report](#phase-6-presentation--report)
- [Part III: Rubric → action map](#part-iii-rubric--action-map)
- [Part IV: Feature → rubric map](#part-iv-feature--rubric-map)
- [Suggested timeline](#suggested-timeline)

---

# Part I: Overview

## What the project is

We have about 100 years of hockey history (1909–2009) in 22 CSV tables, in [`Data/`](Data/). We have to build ML models that, **the day before a new season starts**, predict:

- **(a)** the final regular-season ranking of the teams;
- **(b)** which teams will change coaches;
- **(c)** a third task, still to be announced.

We deliver one presentation of at most 40 slides. It is both the 15-minute talk and the report, with the extra detail in annexes. We also submit the code and data needed to reproduce the results.

**Grade** = (75% submitted assignment + 25% presentation) × individual factor. The individual factor is normally 1, and it goes on the cover slide.

## The three rules that matter most

1. **Follow CRISP-DM.** The rubric is organised exactly by its phases: Business Understanding (BU), Data Understanding (DU), Data Preparation (DP), Modelling, Evaluation. The work, the repo and the slides should be structured the same way.
2. **No information from the future.** We predict the day before the season starts, so every feature for season *t* must come from seasons *t-1, t-2, …*. Using season-*t* stats (W, GF, Pts of the season being predicted) is **leakage**, and it sinks several rubric lines.
3. **Talk to the professor often.** They play the "client". Several rubric lines only reach the top level if we interacted with them, refined the goals and showed the iterations. Keep a log of every meeting.

## Facts about the data

- Years 1909–2009. **2004 is missing** (NHL lockout).
- Leagues: NHA, PCHA, NHL, WCHL, WHA. Only the NHL matters for modern predictions.
- 30 NHL teams per season from 2001 on.
- `Teams.rank` is the rank **within the division**, not league-wide.
- Rules changed over time: ties disappear after 2004, `OTL` (overtime losses) starts in 1999, shootouts (`SoW`, `SoL`) start in 2005. Older seasons have fewer games.
- A team can change `tmID` when it relocates. `franchID` stays constant, so use it to follow a team across years.

---

# Part II: Step-by-step guide (CRISP-DM)

## Phase 0: Project management

1. **Methodology.** We use CRISP-DM because it is iterative and fits a predictive DM project. Keep a short document per phase in `docs/` (goals, decisions, results) and a short reflection at the end of each phase. The top rubric level says "a methodology was followed carefully, **reflecting on the documentation produced**".
2. **Plan.** A Gantt-style plan with tasks, dates and deliverables, aligned with the intermediate dates on Moodle. Update it every week and keep the old versions. Show planned vs actual in an annex slide.
3. **Tools:**
   - **GitHub repo** for code and data.
   - **GitHub Projects** (or Trello/Jira) as the task board. Every task has an owner, a deadline and a link to the code.
   - **Discord/WhatsApp** for communication.
   - **`docs/`** for meeting notes and the decision log.
4. **Repo structure:**
   ```
   Data/                original CSVs (never modified)
   data/processed/      generated datasets
   sql/                 SQL scripts (DB creation, queries)
   notebooks/           01_eda, 02_quality, 03_prep, 04_task_a, 05_task_b
   src/                 reusable functions (features, validation, metrics)
   docs/                plan, meeting notes, decision log
   slides/
   ```

## Phase 1: Business Understanding

### 1.1 Requirements meeting with the professor

Bring these questions:

| Question | Why it matters |
|---|---|
| For (a), is "ranking" the division `rank` column, the conference ranking, or a league-wide ranking by points? | Changes the target variable and the metric. |
| For (a), only NHL? Which season is the test season: 2010 (not in the data) or a held-out season? | Defines the experimental setup. |
| For (b), does "change coach" mean a mid-season change (more than one coach that season) or a change between seasons? | The Coaches table has a row per coach per team per season, with `stint`. If the opening coach is already known the day before the season, the meaningful question is probably "will the team fire its coach during the season?". |
| Can we assume the roster for the new season is known the day before? | Decides whether we may aggregate stats of the players on the team in season *t*. Players traded mid-season can leak. |
| What matters more for (b): catching all changes (recall) or not raising false alarms (precision)? | Decides the main metric and the decision threshold. |
| Why would a club want these predictions (budget, tickets, media, betting)? | Additional business information, which the top rubric level asks for. |

Write the answers in `docs/meetings.md`, with the date.

### 1.2 Business goals → data mining goals

| Business goal | DM goal | Type | Main metric | Success criterion |
|---|---|---|---|---|
| Know how teams will finish | Predict each team's points percentage `Pts / (2·G)` for season *t*, then sort the teams (within division and league) | **Regression**, then ranking | Spearman ρ between predicted and real ranking (per season, averaged); MAE in rank positions | Beat the "same as last season" baseline |
| (optional) Will the team make the playoffs? | Predict `playoff` yes/no | **Classification** | ROC-AUC, F1 | Beat the baseline |
| Know which teams will change coach | Predict whether the team has a coach change in season *t* | **Binary classification** (imbalanced) | PR-AUC, ROC-AUC; F1 / recall of the positive class | Beat the baselines |

**Why predict points and not rank directly?** Rank is relative and depends on the other teams. Predicting a continuous score (points%) and sorting it gives the ranking, and it works for any grouping (division, conference, league). It also gives us **classification and regression** in the same project, which is the top level of "diversity of tasks".

## Phase 2: Data Understanding

### 2.1 Put the data in a database

Load every CSV into **DuckDB** (simplest: one file, SQL straight on pandas) or SQLite/PostgreSQL:

```python
import duckdb, glob, os
con = duckdb.connect("hockey.duckdb")
for f in glob.glob("Data/*.csv"):
    name = os.path.basename(f)[:-4]
    con.execute(f"CREATE OR REPLACE TABLE {name} AS SELECT * FROM read_csv_auto('{f}')")
```

Do as much exploration and preparation as possible **in SQL**: joins, aggregations per team and season, duplicate checks, consistency checks, lag features with window functions. Save the queries in `sql/`.

### 2.2 Get to know each table

For each table, note the years it covers, its granularity (one row = what?), its keys, the % missing per column, and what it is useful for. Some tables only cover a few years: `TeamsHalf`, `ScoringSup`, the shootout tables, the SC tables. Decide which ones are useless for the predictions, justify it, and move on.

### 2.3 Statistical methods (diverse and justified)

For each method, write **why** it is used and **what we concluded**.

| Method | Question it answers |
|---|---|
| Descriptive statistics, distributions per era | How did the game change? (goals per game, ties, OTL) |
| Pearson/Spearman correlation | Which team stats move together? Which are redundant? |
| **Autocorrelation** of points% between *t-1* and *t* | How predictable is a team from last season? Justifies the baseline and the lag features. |
| Mann-Whitney / t-test | Did teams that changed coach have a lower win% last season? |
| Chi-square | Is missing the playoffs associated with a coach change? |
| **PCA** (3+ dimensions) | Are there "team profiles" (offensive, defensive, penalised)? |
| **Clustering** (k-means on the PCA components) | Do the clusters correspond to good and bad teams, or to teams that change coaches? |
| Regression-to-the-mean analysis | Do teams that overperformed (luck) fall back the following season? |

The top levels need "complex 3+D methods with clear results" and "interesting, novel and non-trivial knowledge". So go beyond "teams that win more have more points". Look for things like these:

- **Goal differential predicts next season better than wins.**
- **Teams that won more than their goal differential suggests (luck) get worse the next season.**
- **Coaches are fired more often in their first two seasons, or after missing the playoffs.**

### 2.4 Plots (diverse, justified, some multi-dimensional)

- Line plot of average goals per game and % ties per season (eras, rule changes).
- Correlation heatmap of team features.
- Scatter of points% at *t-1* vs *t*, coloured by coach change and sized by goal differential.
- Pairplot of the main features, coloured by playoff qualification.
- PCA biplot with the clusters.
- Boxplots of win% for teams with and without a coach change.
- Bar chart of coach changes per season.

Every plot in the slides gets a **one-line takeaway as its title**, for example "Goal differential at t-1 explains 50% of the variance of points% at t". The rubric grades interpretation and knowledge extraction, not just the plots. The main plots go in 2 slides and the rest in annexes.

## Phase 3: Data Preparation

### 3.1 Data integration

- **Matching entities across sources:**
  - Follow teams over time with `franchID`, not `tmID`, because of relocations. Use `abbrev` to decode the codes.
  - Link `Coaches` and `Scoring`/`Goalies` with `Master` through `coachID`/`playerID` (coach's age, whether the coach was a former player).
  - Link players to `AwardsPlayers` and `HOF`.
- **Converting formats:**
  - Birth date fields → age at season start.
  - Height and weight → numeric.
  - `T`/`OTL`, which change meaning across eras → one consistent "non-win, non-loss" column.
  - Normalise everything **per game**, because seasons have different lengths.

### 3.2 Data quality: all 6 dimensions

| Dimension | Check on this data |
|---|---|
| **Completeness** | % missing per column and era (e.g. `PPG`, `PIM` missing in early years) |
| **Accuracy** | Cross-check: team `GF` in `Teams` vs the sum of player goals in `Scoring` for that team and season |
| **Consistency** | `W + L + T + OTL = G`? `Pts = 2W + T + OTL`? Coaches' games for a team add up to the team's games? |
| **Uniqueness** | Duplicate (year, tmID) in `Teams`? Duplicate people in `Master`? |
| **Validity** | Negative values, ranks out of range, games > season length |
| **Timeliness** | Data ends in 2009; some tables only cover recent years; are old seasons still representative? |

### 3.3 Sampling for the domain

Keep **NHL only**, from a modern era: e.g. **1979** (the WHA merger) or the **1990s**. Justify the choice with EDA plots showing how the game, the number of teams and the rules changed.

### 3.4 Missing values

- Separate **structural** missing values (the stat did not exist in that era → drop the feature or restrict the era) from **real** missing values.
- **Expansion teams** have no previous season, so their lag features are missing. Impute them with a domain prior (e.g. the historical average of expansion teams' first seasons) and add an `is_new_team` flag.
- For the remaining gaps, use a **model-based imputer** (`KNNImputer`, `IterativeImputer`) **fitted on the training data only**, inside the pipeline.

### 3.5 Outliers

1. **Identify:** IQR or z-score on per-game stats, plus Isolation Forest for multivariate outliers.
2. **Discuss** in hockey terms: shortened seasons (1994: 48 games), historically dominant or terrible teams, players with huge PIM (enforcers), expansion teams.
3. **Address:** per-game normalisation (removes the short-season effect), winsorisation, and a robustness check that keeps the real extreme teams.

### 3.6 Feature engineering (the most important part for performance)

All features use data **up to season t-1**. Build them as one row per (franchise, season):

```python
df = df.sort_values(["franchID", "year"])
g = df.groupby("franchID")
df["pts_pct_lag1"] = g["pts_pct"].shift(1)
df["pts_pct_ma3"]  = g["pts_pct"].transform(lambda s: s.shift(1).rolling(3, min_periods=1).mean())
```

Or in SQL: `LAG(pts_pct) OVER (PARTITION BY franchID ORDER BY year)`.

- **Team (simple):** points% lag1/lag2, 3-season moving average, GF/GA per game, goal differential per game, PP% (`PPG/PPC`), PK% (`1 - PKG/PKC`), PIM per game, home and road win%, playoff result last season.
- **Business concepts:**
  - **Pythagorean expectation** `GF² / (GF² + GA²)`, the "deserved" win%.
  - **Luck** = real win% − Pythagorean win%. Lucky teams tend to drop the following season.
  - **Save%** of the main goalie last season (`1 - GA/SA`, from `Goalies`).
  - **Form trend** = points% at t-1 − at t-2.
- **Roster aggregation (only if the professor confirms the roster is known):**
  - For each team in season *t*, aggregate **its players' stats from t-1**: total points, number of 20+-goal players, average age, award winners.
  - If the roster is not allowed, use the "returning players" of t-1 (players on the team in both t-1 and t-2).
- **Coach (task b):**
  - Tenure with the team; career win%; awards (`AwardsCoaches`).
  - Former player? Age.
  - Underperformance relative to expectations last season; missed the playoffs last season.
  - Franchise coach changes in the last 5 years (some owners fire more).

### 3.7 Redundancy

Compute the correlation matrix and **systematically** remove one of each pair above a fixed threshold (e.g. |ρ| > 0.9), such as `W` vs `Pts` or `GF` vs `PPG`. Also remove IDs and constant columns. Document the threshold and the list of removed features.

### 3.8 Transformations for the algorithms

- **Rescaling:** `StandardScaler` for kNN, SVM, linear/logistic regression and MLP. Trees don't need it; say why.
- **Discretisation** where it is adequate: supervised (MDLP) or quantile binning (`KBinsDiscretizer`) for Naive Bayes and interpretable rules (e.g. coach tenure → new, established, veteran).
- Everything inside a `Pipeline`, so it is fitted only on training data.

### 3.9 Imbalanced data (task b)

Coach changes are the minority class (check the actual %). Compare three options: no resampling, `class_weight="balanced"`, and **SMOTE applied only inside the training folds**:

```python
from imblearn.pipeline import Pipeline
from imblearn.over_sampling import SMOTE
pipe = Pipeline([("imp", KNNImputer()), ("sc", StandardScaler()),
                 ("smote", SMOTE()), ("clf", RandomForestClassifier())])
```

Applying SMOTE to the whole dataset before splitting is the classic error the rubric penalises.

### 3.10 Feature selection

Use both, **inside the validation** (fitted on training data only):

1. **Filter:** mutual information or correlation with the target, keep the top k.
2. **Wrapper:** `RFE` or `SequentialFeatureSelector` with the model.

Show how performance changes with the number of features.

### 3.11 Sampling for development

Start small (e.g. 5 seasons) to debug the pipeline quickly. Then grow to 10 seasons and then the full modern era, recording the metric at each size. Show the learning curve in an annex.

## Phase 4: Modelling

### 4.1 Experimental setup: temporal validation (the most important slide)

**Never use random k-fold**: it trains on the future to predict the past. Use **walk-forward (expanding window)**:

```
train: 1980–1999 → test: 2000
train: 1980–2000 → test: 2001
...
train: 1980–2008 → test: 2009
```

```python
results = []
for test_year in range(2000, 2010):
    if test_year == 2004:
        continue
    tr, te = df[df.year < test_year], df[df.year == test_year]
    model.fit(tr[X], tr[y])
    results.append(evaluate(te, model.predict(te[X])))
```

- This gives **multiple splits** and takes **time** into account correctly.
- Each test season gives one result per model, which we use for the statistical tests.
- Hyperparameter tuning uses an inner temporal split inside each training set. Never tune on the test season.

### 4.2 Algorithms (4 or more, with different "language bias")

| Algorithm | Bias | (a) | (b) |
|---|---|---|---|
| Linear / Ridge / Lasso regression, Logistic regression | linear | ✔ | ✔ |
| Decision tree | axis-parallel rules (white-box) | ✔ | ✔ |
| kNN | distance / similarity | ✔ | ✔ |
| SVM / SVR | margin / kernel | ✔ | ✔ |
| Naive Bayes | probabilistic, independence | – | ✔ |
| Random Forest | bagged ensemble | ✔ | ✔ |
| Gradient Boosting (XGBoost / LightGBM) | boosted ensemble | ✔ | ✔ |
| MLP | neural network | ✔ | ✔ |

For each one, we must be able to explain **how it works** and **what its main parameters do**. For example: "deeper trees memorise the training seasons, so test performance drops", "a larger k in kNN smooths the predictions".

### 4.3 Parameter tuning (systematic)

Grid, random or Optuna search with temporal inner validation. Show **validation curves** (score vs one parameter, with training and validation curves on the same plot).

### 4.4 Analytics tools

Python is the main tool: pandas, scikit-learn, imbalanced-learn, XGBoost, SHAP. Reproduce part of the work (e.g. task b with 2–3 algorithms) in **KNIME or Orange** and show the workflow in an annex.

## Phase 5: Evaluation

### 5.1 Baselines (mandatory)

- **(a):** "Same ranking as last season". It is surprisingly strong, and beating it is the real goal. Also a trivial one: "league average for every team".
- **(b):**
  - The majority class ("nobody changes"). It has high accuracy but zero recall, which shows why accuracy is a bad metric here.
  - A simple rule: "teams that missed the playoffs change coach".

### 5.2 Metrics: aligned with the goals and the data

- **(a):** Spearman ρ and Kendall τ (ranking quality); MAE in rank positions ("on average we miss by 2.1 places"); MAE/RMSE on points%. Playoff classification: ROC-AUC.
- **(b):** **PR-AUC** (best for an imbalanced class), ROC-AUC, and precision, recall and F1 of the positive class. Tune the decision threshold according to the professor's answer about precision vs recall.
- Explain **why** each metric fits: accuracy misleads with imbalance, and ranking metrics only care about order.

### 5.3 Comparison and statistical significance

- Table of mean ± standard deviation over the test seasons for every model and baseline.
- **Friedman test** (each test season is a block), then **Nemenyi post-hoc** with a critical-difference diagram. Also **Wilcoxon signed-rank** for best model vs baseline.
- Conclude carefully, e.g. "RF beats the baseline (p = 0.03), but RF and XGBoost are not significantly different".

### 5.4 Overfitting

- Training score next to test score for every model.
- Learning curves (vs training size) and validation curves (vs complexity).
- Interpret them, e.g. "the deep tree reaches ρ = 0.98 on training and 0.45 on test; limiting depth to 4 closes the gap".

### 5.5 Model improvement log

Keep a table where each row is one iteration:

| # | Change | Spearman ρ (a) | Decision |
|---|---|---|---|
| 1 | Baseline (rank t-1) | … | – |
| 2 | Lag features + Ridge | … | keep / drop |
| 3 | + Pythagorean / luck | … | … |
| 4 | + roster aggregates | … | … |
| 5 | + feature selection | … | … |

### 5.6 Feature importance and white-box models

- Permutation importance and **SHAP** (summary plot plus one example team).
- **Interpret in hockey terms**, e.g. "last season's goal differential matters more than last season's wins because wins include luck, and luck reverts to the mean".
- Show a shallow **decision tree** (depth 3–4) or the logistic coefficients and read them. For example: "IF missed playoffs AND coach tenure ≤ 2 THEN high chance of change". Then discuss whether the rules make sense for hockey.

### 5.7 Final predictions

Retrain the best model on all available seasons and produce the predictions for the target season: the predicted ranking per division, and the list of teams likely to change coach with their probabilities.

## Phase 6: Presentation / report

### Structure (at most 40 slides, 15 minutes)

| Slides | Content |
|---|---|
| 1 | Cover: group, names, **individual factor (IF) of each student** |
| 1 | Domain description |
| 2 | EDA: main findings, plots with takeaway titles |
| 1 | Problem definition: business goals → DM goals table |
| 2 | Data preparation: integration, quality, features, imbalance, selection |
| 1 | Experimental setup: walk-forward diagram, metrics, baselines |
| 2 | Results: comparison + statistical test; feature importance + final predictions |
| 1 | Conclusions, limitations, future work |
| ≤ 29 | **Annexes:** plan/Gantt, data quality table, extra EDA, all models, tuning curves, decision tree, iteration log, tool screenshots |

### Tips

- About 1 minute per main slide. Rehearse with a timer.
- One message per slide, with little text, a clear plot and the takeaway as the title.
- Be honest about limitations: the data ends in 2009, mid-season trades can't be seen, coaching decisions depend on things not in the data (owners, contracts).
- Submit the slides **plus** everything needed to reproduce the results: code, data, and a README explaining how to run it.

---

# Part III: Rubric → action map

How to read it: each row is one line of the grading grid.

- **Target level** is the top level we aim for, quoted from the rubric.
- **What we do** is the concrete action.
- **Evidence** is what the grader must see, and where it appears.

**If an action has no visible evidence, it doesn't count for the grade.**

## 1. Business Understanding (BU)

| Criterion | Target level | What we do | Evidence |
|---|---|---|---|
| **Analysis of requirements with the end user** | "extensive identification of business objectives **and additional relevant business information**" | Meet the professor with the prepared questions (§1.1), including business context. | `docs/meetings.md`; annex slide "Requirements gathering". |
| **Definition of business goals** | "clearly and quickly identified goals" | Write the goals after the first meeting; refine at most once and record why. | Problem definition slide; decision log. |
| **Translation into DM goals** | "DM goals clearly aligned with business goals" | (a) → regression of points% + ranking (+ playoff classification); (b) → imbalanced binary classification; each with a metric and a success criterion. | Table on the problem definition slide. |

## 2. Data Understanding (DU): statistics

| Criterion | Target level | What we do | Evidence |
|---|---|---|---|
| **Diversity of statistical methods** | "rich and **justified** set" | Descriptive statistics, correlations, t-test/Mann-Whitney, chi-square, autocorrelation, PCA, k-means, each with one sentence of "why". | EDA notebook; annex table method → question → result. |
| **Complexity of statistical methods** | "**integrated**, complex 3+D methods with clear results" | PCA → k-means on the components → cross the clusters with playoff and coach-change rates. | PCA biplot by cluster + table cluster → % playoffs → % coach changes. |
| **Interpretation of statistical results** | "generally correct" | Every number gets a correct sentence (association ≠ causation, correct meaning of p-values). | Takeaway text under every result. |
| **Knowledge extraction (statistics)** | "interesting, **novel and non-trivial**" | Goal differential > wins as a predictor; luck reverts to the mean; early-tenure coaches fired more; franchise effect. | 2 EDA slides with these as headlines. |

## 3. Data Understanding (DU): visualisation

| Criterion | Target level | What we do | Evidence |
|---|---|---|---|
| **Diversity of plots** | "rich and **justified** set" | Line, heatmap, scatter, boxplot, bar, pairplot, PCA biplot, each with why that plot type fits. | Plot gallery annex with one-line justifications. |
| **Complexity of plots** | "integrated, complex 3+D plots with clear results" | Scatter points% t-1 vs t, coloured by coach change and sized by goal differential; pairplot coloured by playoff; PCA biplot with clusters. | Best 2–3 on the EDA slides. |
| **Presentation** | "well-structured information" | Plots grouped by question; consistent colours, labels and units; the title of each plot is its conclusion. | EDA slides + annexes. |
| **Interpretation of plots** | "generally correct" | A correct, non-over-claiming sentence for each plot. | Caption or title. |
| **Visual knowledge extraction** | "interesting, novel and non-trivial" | The same findings made visible: the regression-to-the-mean scatter, the coach-tenure firing curve. | EDA slides. |

## 4. Data Preparation (DP)

| Criterion | Target level | What we do | Evidence |
|---|---|---|---|
| **Data integration** | "conversion of formats **AND** matching entities between sources" | Matching: `franchID` + `abbrev`; `Coaches`/`Scoring`/`Goalies` ↔ `Master`; ↔ `AwardsPlayers`/`HOF`. Conversion: birth fields → age, T/OTL harmonised, per-game stats. | Prep slide; `sql/` scripts. |
| **Data quality dimensions** | "6 dimensions" | Completeness, accuracy, consistency, uniqueness, validity, timeliness (§3.2). | Annex table dimension → check → result → fix. |
| **Redundancy** | "**systematic** removal" | Fixed correlation threshold over all feature pairs + IDs and constant columns. | Annex: threshold + removed list + heatmap before/after. |
| **Missing data** | "complex method with **correct experimental setup**" | `IterativeImputer`/`KNNImputer` inside the pipeline (training only); domain prior + flag for expansion teams. | Prep slide + pipeline code ("fitted on training only"). |
| **Outliers** | "identify, discuss, address with **complex/domain-dependent** approaches" | IQR/z-score + Isolation Forest; hockey discussion; per-game normalisation + winsorisation. | Annex: outlier table + discussion + before/after. |
| **Transformation for algorithms** | "adequate **complex** discretisation or rescaling" | Scaling only where needed (with justification); supervised (MDLP) or quantile discretisation for NB and rules. | Prep slide: transformation → algorithm → why. |
| **Feature engineering** | "complex methods (aggregation) **AND** knowledge (business concepts)" | Roster/coach/franchise aggregations + Pythagorean, luck, save%, PP%/PK%. See Part IV. | Feature table: feature → formula → hockey meaning. |
| **Sampling for domain** | "focus on **adequate** subset" | NHL only, modern era, justified with EDA plots. | Prep slide + eras plot. |
| **Sampling for development** | "start very small, grow to significant" | 5 → 10 → all seasons, metric recorded at each size. | Annex learning curve. |
| **Imbalanced data** | "SMOTE used **correctly**" | SMOTE inside `imblearn.Pipeline`; compared with no resampling and class weights. | Results annex table + code. |
| **Feature selection** | "correct, **combined** filter and wrapper" | Mutual information top-k → RFE/SFS, inside the training of each split. | Annex: performance vs number of features + final list. |

## 5. Predictive modelling

| Criterion | Target level | What we do | Evidence |
|---|---|---|---|
| **Diversity of tasks** | "classification **AND** regression" | (a) regression (+ playoff classification); (b) classification. | Problem definition slide. |
| **Diversity of algorithms** | "4+ with significantly different language bias" | Linear/logistic, tree, kNN, SVM, NB, RF, XGBoost, MLP. | Results table. |
| **Parameter tuning** | "systematic approach" | Grid/random/Optuna search with temporal inner validation, the same procedure for every algorithm. | Annex: search spaces, best parameters, validation curves. |
| **Understanding algorithm behaviour** | "solid understanding of the **majority** of algorithms, **also the effect of the parameters**" | One line on how each algorithm works + one validation curve per algorithm, explained. | Annex slides; preparation for questions in the talk. |

## 6. Performance estimation

| Criterion | Target level | What we do | Evidence |
|---|---|---|---|
| **Training vs test** | "correctly separated, with **multiple splits**" | Walk-forward 2000–2009 (skip 2004); all fitting inside training. | Setup slide with the walk-forward diagram. |
| **Other factors (e.g. time)** | "**correctly** taken into account" | Only t-1 information for season t; no random k-fold; eras and expansion teams handled. | Setup slide: "No information from season t is used". |
| **Performance measure** | "aligned with DM goals **and data characteristics**" | (a): Spearman + rank MAE; (b): PR-AUC + F1 of the positive class (imbalance). | Setup slide: metric → why. |
| **Interpretation of measures** | "advanced measures (e.g. AUC)" | ROC-AUC and PR-AUC used and explained, with the PR-AUC compared to the random baseline (= the positive rate). | Results slide text. |
| **Baseline** | "suitable baseline" | (a): last season's ranking. (b): majority class + the "missed playoffs" rule. | Rows in the results table. |
| **Analysis of results** | "including **tests** for statistical significance" | Friedman + Nemenyi (CD diagram); Wilcoxon best vs baseline. | Results slide. |
| **Analysis of overfitting** | "correct estimation, **correctly analysed**" | Training vs test per model; learning and validation curves, with explanations. | Results annex. |

## 7. Model improvement and interpretation

| Criterion | Target level | What we do | Evidence |
|---|---|---|---|
| **Model improvement** | "guided by performance improvement goals" | Iteration log: change → metric before/after → keep or drop. | Annex table (+ line chart over iterations). |
| **Feature importance** | "interpreted correctly, **relating to application domain**" | Permutation + SHAP, read in hockey terms. | Results slide with SHAP + a 2-line interpretation. |
| **White-box models** | "interpreted correctly, relating to application domain" | Shallow tree + logistic coefficients; rules in plain language; do they make hockey sense? | Annex with the tree plot + rules. |

## 8. Project management and tools

| Criterion | Target level | What we do | Evidence |
|---|---|---|---|
| **Methodology** | "followed carefully, **reflecting on the documentation**" | CRISP-DM, a doc per phase in `docs/` + a short reflection at the end of each phase. | Annex: CRISP-DM cycle with our actual iterations. |
| **Plan** | "**detailed** plan that guided development" | Gantt updated every week; old versions kept. | Annex: planned vs actual Gantt. |
| **PM tools** | "detailed task sharing with appropriate tool" | GitHub Projects: each task has an owner, a deadline and a linked commit/PR. | Annex: board screenshot. |
| **Collaboration tools** | "easy collaboration (communication, data, workflows, documentation)" | Discord + GitHub + shared `src/` + `docs/` + README. | Annex: tools → role. |
| **Analytics tools** | "**multiple** tools from the courses" | Python + KNIME/Orange. | Annex: workflow screenshot + result comparison. |
| **Database** | "**extensive** use for exploration and preparation" | DuckDB/SQLite: joins, aggregations, quality checks, lag features via `LAG() OVER (PARTITION BY franchID ORDER BY year)`. | `sql/` + annex with 2–3 example queries. |
| **Other tools** | "extensive and correct use" | matplotlib/seaborn/plotly; ydata-profiling or OpenRefine for quality; Git. | Profiling report in an annex; plots throughout. |

## 9. Presentation

| Criterion | Target level | What we do |
|---|---|---|
| **Quality of layout** | "simple AND clear" | One template, little text, large plots, the title of each slide is its message. |
| **Quality of content** | "to the point" | About 13 main slides in the suggested structure; everything else in annexes. |
| **Delivery** | "clear AND with confidence" | Each person presents what they built; rehearse at least twice. |
| **Use of time** | "to the point" | 15 minutes ≈ 1 minute per main slide; rehearse with a timer. |

---

# Part IV: Feature → rubric map

Each feature we build also counts toward specific criteria:

| Feature | How it's built | Rubric criteria it feeds |
|---|---|---|
| `pts_pct_lag1`, `pts_pct_lag2` | `LAG()` per franchID | Feature engineering (simple); Time factor; Database |
| `pts_pct_ma3` | Mean over t-1…t-3 | Feature engineering (**aggregation**); Time factor |
| `goal_diff_pg_lag1` | (GF − GA)/G at t-1 | Feature engineering (knowledge); Transformation (per game); Outliers (per-game fix) |
| `pythag_lag1` | GF²/(GF²+GA²) at t-1 | Feature engineering (**business concept**); Knowledge extraction |
| `luck_lag1` | win% − pythag at t-1 | Feature engineering (**business concept**); Novel knowledge (reversion to the mean) |
| `pp_pct_lag1`, `pk_pct_lag1` | PPG/PPC, 1 − PKG/PKC | Feature engineering (business concept); Missing data (absent in old eras) |
| `save_pct_main_goalie_lag1` | 1 − GA/SA of the goalie with the most minutes | **Integration** (Goalies ↔ Teams); Feature engineering (aggregation + concept) |
| `roster_pts_lag1`, `n_20goal_players`, `avg_age` | Players on the team, their t-1 stats summed or averaged | **Integration** (Scoring ↔ Master); Feature engineering (**aggregation**); Format conversion (birth date → age) |
| `n_award_winners`, `n_hof_players` | Join AwardsPlayers / HOF | **Integration** (matching entities) |
| `coach_tenure` | Consecutive seasons of the coach with the franchise | Feature engineering (aggregation + concept); Discretisation (new/established/veteran) |
| `coach_career_winpct` | Coach W/G over all past seasons | Feature engineering (**aggregation**) |
| `coach_is_former_player`, `coach_age` | Master: coachID & playerID | **Integration** (matching entities); Format conversion |
| `franchise_changes_5y` | Coach changes of the franchise in the last 5 seasons | Feature engineering (aggregation + concept: impatient owners) |
| `missed_playoffs_lag1` | `playoff` at t-1 | Feature engineering (simple); Baseline rule for (b) |
| `underperformance_lag1` | Real points − expected points at t-1 | Feature engineering (**business concept**); White-box rules |
| `is_new_team` | Expansion or relocation without history | **Missing data** (domain prior); **Outliers** (domain-dependent) |

**The three most important ideas to remember:**

1. **Everything uses "t-1"**, which keeps the setup free of leakage.
2. **Everything is fitted inside the pipeline**, which makes the experimental setup correct.
3. **Every result gets a hockey interpretation**, which lifts "correct" to "relating to the application domain".

---

# Suggested timeline

Adjust it to the dates on Moodle.

| Week | Focus |
|---|---|
| 1 | Setup (repo, board, DB), BU meeting with the professor, first EDA |
| 2 | Finish EDA, data quality, decide the era |
| 3–4 | Integration, cleaning, feature engineering, baselines |
| 5–6 | Models for (a) and (b), walk-forward validation, tuning; task (c) once announced |
| 7 | Evaluation: statistical tests, overfitting, feature importance, final predictions |
| 8 | Slides, annexes, reproducibility check, rehearsal |

Keep the code modular (feature functions, the walk-forward loop and the metrics in `src/`) so task (c) can be plugged in quickly when it is announced.
