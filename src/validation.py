"""Temporal validation, metrics and statistical tests shared by the modelling notebooks.

Walk-forward (expanding window): to evaluate season T we train on every season < T
and test on season T. This never uses the future to predict the past.
"""
import numpy as np
import pandas as pd
from scipy import stats
from sklearn.base import BaseEstimator, TransformerMixin, clone
from sklearn.metrics import (average_precision_score, f1_score, mean_absolute_error,
                             precision_score, recall_score, roc_auc_score)

MIN_YEAR = 1979                      # WHA merger: start of the modern NHL (justified in 03)
TEST_YEARS = [y for y in range(2000, 2010) if y != 2004]   # 2004: lockout, no season


# ---------------------------------------------------------------------------
# Splits
# ---------------------------------------------------------------------------
def walk_forward(df, test_years=TEST_YEARS, min_year=MIN_YEAR, train_window=None):
    """Yield (test_year, train_df, test_df). train_window=k keeps only the last k seasons."""
    for ty in test_years:
        tr = df[(df.year < ty) & (df.year >= min_year)]
        if train_window is not None:
            keep = sorted(tr.year.unique())[-train_window:]
            tr = tr[tr.year.isin(keep)]
        yield ty, tr, df[df.year == ty]


def inner_temporal_cv(years, n_folds=3):
    """Inner splits for tuning INSIDE a training set: validate on each of the last
    n_folds seasons, training on the seasons before it. Returns a list usable as cv=."""
    years = np.asarray(years)
    uniq = sorted(np.unique(years))
    folds = []
    for vy in uniq[-n_folds:]:
        folds.append((np.where(years < vy)[0], np.where(years == vy)[0]))
    return folds


# ---------------------------------------------------------------------------
# Transformers used inside pipelines (fitted on training data only)
# ---------------------------------------------------------------------------
class Winsorizer(BaseEstimator, TransformerMixin):
    """Clip each column to the [lower, upper] quantiles seen in the TRAINING data."""

    def __init__(self, lower=0.01, upper=0.99):
        self.lower, self.upper = lower, upper

    def fit(self, X, y=None):
        X = np.asarray(X, dtype=float)
        self.lo_ = np.nanquantile(X, self.lower, axis=0)
        self.hi_ = np.nanquantile(X, self.upper, axis=0)
        return self

    def transform(self, X):
        return np.clip(np.asarray(X, dtype=float), self.lo_, self.hi_)


class FilterWrapperSelector(BaseEstimator, TransformerMixin):
    """Combined feature selection, fitted on the training data only.
    1. FILTER: keep the filter_k features with the highest mutual information with y;
    2. WRAPPER: Recursive Feature Elimination with a linear model keeps k of them.
    k=None keeps every feature (lets the grid search decide whether selecting helps)."""

    def __init__(self, k=None, filter_k=None, task="regression"):
        self.k, self.filter_k, self.task = k, filter_k, task

    def fit(self, X, y):
        from sklearn.feature_selection import RFE, mutual_info_classif, mutual_info_regression
        from sklearn.linear_model import LogisticRegression, Ridge
        from sklearn.preprocessing import StandardScaler
        X = np.asarray(X, dtype=float)
        n = X.shape[1]
        self.support_ = np.ones(n, bool)
        if self.k is None or self.k >= n:
            return self
        fk = min(n, self.filter_k or 2 * self.k)
        mi_fn = mutual_info_regression if self.task == "regression" else mutual_info_classif
        self.mi_ = mi_fn(X, y, random_state=0)
        top = np.argsort(self.mi_)[::-1][:fk]
        Xs = StandardScaler().fit_transform(X[:, top])
        est = Ridge(alpha=1.0) if self.task == "regression" else LogisticRegression(C=0.1, max_iter=5000)
        rfe = RFE(est, n_features_to_select=self.k).fit(Xs, y)
        self.support_ = np.zeros(n, bool)
        self.support_[top[rfe.support_]] = True
        return self

    def transform(self, X):
        return np.asarray(X, dtype=float)[:, self.support_]


# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------
def ranking_metrics(test, pred):
    """Task (a). test has columns pts_pct, confID, divID, made_playoffs; pred = predicted pts%."""
    t = test.assign(pred=np.asarray(pred))
    out = {
        "spearman": stats.spearmanr(t.pred, t.pts_pct)[0],
        "kendall": stats.kendalltau(t.pred, t.pts_pct)[0],
        "rank_mae": mean_absolute_error(t.pts_pct.rank(ascending=False), t.pred.rank(ascending=False)),
        "pts_mae": mean_absolute_error(t.pts_pct, t.pred),
    }
    # ranking inside each division, averaged
    div = [stats.spearmanr(d.pred, d.pts_pct)[0] for _, d in t.groupby("divID") if len(d) > 2]
    out["div_spearman"] = np.nanmean(div)
    # playoffs: the top 8 of each conference by predicted points qualify (format since 1994)
    t["pred_playoff"] = (t.groupby("confID")["pred"].rank(ascending=False) <= 8).astype(int)
    out["playoff_acc"] = (t.pred_playoff == t.made_playoffs).mean()
    out["playoff_auc"] = roc_auc_score(t.made_playoffs, t.pred) if t.made_playoffs.nunique() > 1 else np.nan
    return out


def classification_metrics(y, proba, threshold=0.5):
    """Task (b). PR-AUC is the main metric (imbalanced positive class)."""
    y = np.asarray(y).astype(int)
    pred = (np.asarray(proba) >= threshold).astype(int)
    two = len(np.unique(y)) > 1
    return {
        "pr_auc": average_precision_score(y, proba) if two else np.nan,
        "roc_auc": roc_auc_score(y, proba) if two else np.nan,
        "f1": f1_score(y, pred, zero_division=0),
        "precision": precision_score(y, pred, zero_division=0),
        "recall": recall_score(y, pred, zero_division=0),
        "pos_rate": y.mean(),
    }


def best_f1_threshold(y, proba):
    """Threshold that maximises F1 on (training / validation) data."""
    grid = np.linspace(0.05, 0.95, 91)
    f1s = [f1_score(y, (proba >= t).astype(int), zero_division=0) for t in grid]
    return float(grid[int(np.argmax(f1s))])


# ---------------------------------------------------------------------------
# Statistical comparison of models over the test seasons
# ---------------------------------------------------------------------------
# Nemenyi critical values q_0.05 (Demsar 2006), index = number of models
_Q05 = {2: 1.960, 3: 2.343, 4: 2.569, 5: 2.728, 6: 2.850, 7: 2.949, 8: 3.031, 9: 3.102,
        10: 3.164, 11: 3.219, 12: 3.268, 13: 3.313, 14: 3.354}


def friedman_nemenyi(scores, higher_is_better=True):
    """scores: DataFrame, rows = test seasons (blocks), columns = models.
    Returns (friedman statistic, p-value, average ranks, critical difference)."""
    s = scores.dropna(axis=1)
    stat, p = stats.friedmanchisquare(*[s[c] for c in s.columns])
    ranks = (-s if higher_is_better else s).rank(axis=1).mean().sort_values()
    k, n = s.shape[1], s.shape[0]
    cd = _Q05[k] * np.sqrt(k * (k + 1) / (6 * n))
    return stat, p, ranks, cd


def plot_cd(ranks, cd, ax, title=""):
    """Simple critical-difference diagram: average rank of each model with a CD bar."""
    ranks = ranks.sort_values()
    y = np.arange(len(ranks))
    ax.hlines(y, ranks.values - cd / 2, ranks.values + cd / 2, color="#bbb", lw=6)
    ax.plot(ranks.values, y, "o", color="#1f4e79")
    ax.set_yticks(y, ranks.index)
    ax.invert_yaxis()
    ax.set_xlabel(f"average rank (lower = better); bar = critical difference {cd:.2f}")
    ax.set_title(title or "Overlapping bars = not significantly different (Nemenyi, α=0.05)")
    ax.grid(axis="x", alpha=.3)


def wilcoxon_vs(scores, a, b):
    """Paired Wilcoxon signed-rank test between two models over the test seasons."""
    return stats.wilcoxon(scores[a], scores[b])
