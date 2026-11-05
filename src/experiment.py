"""Run a set of models through the walk-forward evaluation.

For every test season T:
  1. train = seasons < T, test = season T;
  2. tune hyper-parameters with GridSearchCV on an INNER temporal split of the training
     seasons (validate on each of the last 3 training seasons);
  3. refit the best configuration on the whole training set, predict season T;
  4. (classification) choose the decision threshold that maximises F1 on the inner
     validation predictions, never on the test season.
"""
import warnings

import numpy as np
import pandas as pd
from sklearn.base import clone
from sklearn.model_selection import GridSearchCV

from validation import (best_f1_threshold, classification_metrics, inner_temporal_cv,
                        ranking_metrics, walk_forward)

warnings.filterwarnings("ignore")


def run_regression(df, features, models, target="pts_pct", tune=True, **wf):
    """Task (a). Returns (scores per season and model, predictions, best params)."""
    rows, preds, params = [], [], []
    for name, (pipe, grid) in models.items():
        for ty, tr, te in walk_forward(df, **wf):
            est = _fit(pipe, grid if tune else {}, tr[features], tr[target], tr.year,
                       "neg_mean_absolute_error")
            p = est.predict(te[features])
            m = ranking_metrics(te, p)
            m_tr = ranking_metrics(tr[tr.year == tr.year.max()], est.predict(
                tr[tr.year == tr.year.max()][features]))
            rows.append({"model": name, "year": ty, **m, "train_spearman": m_tr["spearman"],
                         "train_pts_mae": m_tr["pts_mae"]})
            preds.append(te[["year", "franchID", "name", "confID", "divID", "pts_pct",
                             "made_playoffs"]].assign(model=name, pred=p))
            params.append({"model": name, "year": ty, **getattr(est, "best_params_", {})})
    return pd.DataFrame(rows), pd.concat(preds), pd.DataFrame(params)


def run_classification(df, features, models, target, tune=True, **wf):
    """Task (b). Returns (scores per season and model, predictions, best params)."""
    rows, preds, params = [], [], []
    for name, (pipe, grid) in models.items():
        for ty, tr, te in walk_forward(df, **wf):
            tr = tr.dropna(subset=[target])
            te = te.dropna(subset=[target])
            if te.empty:
                continue
            est = _fit(pipe, grid if tune else {}, tr[features], tr[target].astype(int),
                       tr.year, "average_precision")
            thr = _inner_threshold(est, tr, features, target)
            p = est.predict_proba(te[features])[:, 1]
            p_tr = est.predict_proba(tr[features])[:, 1]
            m = classification_metrics(te[target], p, thr)
            m_tr = classification_metrics(tr[target], p_tr, thr)
            rows.append({"model": name, "year": ty, **m, "threshold": thr,
                         "train_pr_auc": m_tr["pr_auc"], "train_roc_auc": m_tr["roc_auc"]})
            preds.append(te[["year", "franchID", "name", target]].assign(model=name, proba=p,
                                                                        pred=(p >= thr).astype(int)))
            params.append({"model": name, "year": ty, **getattr(est, "best_params_", {})})
    return pd.DataFrame(rows), pd.concat(preds), pd.DataFrame(params)


def _fit(pipe, grid, X, y, years, scoring):
    if not grid:
        return clone(pipe).fit(X, y)
    gs = GridSearchCV(clone(pipe), grid, cv=inner_temporal_cv(years.values), scoring=scoring,
                      n_jobs=-1, refit=True, error_score=np.nan)
    gs.fit(X, y)
    return gs


def _inner_threshold(est, tr, features, target):
    """Out-of-sample probabilities on the inner validation seasons -> best F1 threshold."""
    best = est.best_estimator_ if hasattr(est, "best_estimator_") else est
    ys, ps = [], []
    for tr_idx, va_idx in inner_temporal_cv(tr.year.values):
        m = clone(best).fit(tr[features].iloc[tr_idx], tr[target].iloc[tr_idx].astype(int))
        ps.append(m.predict_proba(tr[features].iloc[va_idx])[:, 1])
        ys.append(tr[target].iloc[va_idx].astype(int).values)
    return best_f1_threshold(np.concatenate(ys), np.concatenate(ps))


def summary(scores, cols):
    """mean ± std over the test seasons, one row per model."""
    agg = scores.groupby("model")[cols].agg(["mean", "std"])
    out = pd.DataFrame(index=agg.index)
    for c in cols:
        out[c] = agg[(c, "mean")].round(3).astype(str) + " ± " + agg[(c, "std")].round(3).astype(str)
    out["_sort"] = agg[(cols[0], "mean")]
    return out.sort_values("_sort", ascending=False).drop(columns="_sort")
