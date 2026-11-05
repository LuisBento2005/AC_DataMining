"""Model zoo: one pipeline + parameter grid per algorithm, for regression (task a)
and classification (task b). Every preprocessing step lives inside the pipeline,
so it is fitted on the training seasons only (no leakage into the test season).
"""
from imblearn.over_sampling import SMOTE
from imblearn.pipeline import Pipeline
from sklearn.ensemble import (HistGradientBoostingClassifier, HistGradientBoostingRegressor,
                              RandomForestClassifier, RandomForestRegressor)
from sklearn.experimental import enable_iterative_imputer  # noqa: F401
from sklearn.impute import IterativeImputer, KNNImputer, SimpleImputer
from sklearn.linear_model import LogisticRegression, Ridge, Lasso
from sklearn.naive_bayes import CategoricalNB
from sklearn.neighbors import KNeighborsClassifier, KNeighborsRegressor
from sklearn.neural_network import MLPClassifier, MLPRegressor
from sklearn.preprocessing import KBinsDiscretizer, StandardScaler
from sklearn.svm import SVC, SVR
from sklearn.tree import DecisionTreeClassifier, DecisionTreeRegressor

from validation import FilterWrapperSelector, Winsorizer

SEED = 42


def _prep(scale=True, imputer="knn"):
    """Imputation -> winsorisation -> (scaling). Trees do not need scaling (splits are
    invariant to monotonic transformations), distance/gradient-based models do."""
    imp = {"knn": KNNImputer(n_neighbors=10),
           "iterative": IterativeImputer(max_iter=10, random_state=SEED),
           "median": SimpleImputer(strategy="median")}[imputer]
    steps = [("imp", imp), ("wins", Winsorizer())]
    if scale:
        steps.append(("sc", StandardScaler()))
    return steps


# ---------------------------------------------------------------------------
# Task (a): regression of points%
# ---------------------------------------------------------------------------
FS_K = [8, 16, None]   # number of features kept by the selector (None = all)


def _with_selection(zoo, task, select):
    """Insert the filter+wrapper selector after preprocessing and tune its k."""
    if not select:
        return zoo
    out = {}
    for name, (pipe, grid) in zoo.items():
        steps = list(pipe.steps)
        steps.insert(len(steps) - 1, ("fs", FilterWrapperSelector(task=task)))
        out[name] = (Pipeline(steps), {**grid, "fs__k": FS_K})
    return out


def regressors(select=True):
    return _with_selection(_regressors(), "regression", select)


def _regressors():
    return {
        "Ridge": (Pipeline(_prep() + [("m", Ridge())]),
                  {"m__alpha": [0.1, 1, 10, 100]}),
        "Lasso": (Pipeline(_prep() + [("m", Lasso(max_iter=10000))]),
                  {"m__alpha": [0.0005, 0.002, 0.01]}),
        "kNN": (Pipeline(_prep() + [("m", KNeighborsRegressor())]),
                {"m__n_neighbors": [10, 25, 50], "m__weights": ["uniform", "distance"]}),
        "SVR": (Pipeline(_prep() + [("m", SVR())]),
                {"m__C": [0.1, 1], "m__epsilon": [0.01, 0.03], "m__gamma": ["scale", 0.01]}),
        "Tree": (Pipeline(_prep(scale=False) + [("m", DecisionTreeRegressor(random_state=SEED))]),
                 {"m__max_depth": [2, 3, 4, 6], "m__min_samples_leaf": [10, 30]}),
        "RandomForest": (Pipeline(_prep(scale=False) + [("m", RandomForestRegressor(
                            n_estimators=200, random_state=SEED, n_jobs=-1))]),
                         {"m__max_depth": [4, 8], "m__min_samples_leaf": [5, 20],
                          "m__max_features": [0.3, 0.6]}),
        "GradBoost": (Pipeline(_prep(scale=False) + [("m", HistGradientBoostingRegressor(
                         random_state=SEED))]),
                      {"m__learning_rate": [0.03, 0.1], "m__max_depth": [2, 3],
                       "m__max_iter": [150]}),
        "MLP": (Pipeline(_prep() + [("m", MLPRegressor(max_iter=2000, early_stopping=True,
                                                         random_state=SEED))]),
                {"m__hidden_layer_sizes": [(16,), (32, 16)], "m__alpha": [0.01, 1]}),
    }


# ---------------------------------------------------------------------------
# Task (b): classification of coach change
# ---------------------------------------------------------------------------
def classifiers(balance="weight", select=True):
    return _with_selection(_classifiers(balance), "classification", select)


def _classifiers(balance="weight"):
    """balance: 'none' | 'weight' (class_weight='balanced') | 'smote' (SMOTE inside the
    training folds only, thanks to imblearn's Pipeline)."""
    cw = "balanced" if balance == "weight" else None

    def pipe(steps_prep, model):
        steps = list(steps_prep)
        if balance == "smote":
            steps.append(("smote", SMOTE(random_state=SEED, k_neighbors=5)))
        return Pipeline(steps + [("m", model)])

    zoo = {
        "LogReg": (pipe(_prep(), LogisticRegression(max_iter=5000, class_weight=cw)),
                   {"m__C": [0.01, 0.1, 1]}),
        "kNN": (pipe(_prep(), KNeighborsClassifier()),
                {"m__n_neighbors": [15, 35, 75], "m__weights": ["uniform", "distance"]}),
        "SVM": (pipe(_prep(), SVC(probability=True, class_weight=cw, random_state=SEED)),
                {"m__C": [0.1, 1], "m__gamma": ["scale", 0.01]}),
        # Naive Bayes on discretised features: quantile bins -> categorical NB
        "NaiveBayes": (pipe(_prep(scale=False) + [("disc", KBinsDiscretizer(
                           n_bins=4, encode="ordinal", strategy="quantile"))], CategoricalNB()),
                       {"m__alpha": [0.5, 1, 5]}),
        "Tree": (pipe(_prep(scale=False), DecisionTreeClassifier(class_weight=cw, random_state=SEED)),
                 {"m__max_depth": [2, 3, 4, 6], "m__min_samples_leaf": [10, 30]}),
        "RandomForest": (pipe(_prep(scale=False), RandomForestClassifier(
                            n_estimators=200, class_weight=cw, random_state=SEED, n_jobs=-1)),
                         {"m__max_depth": [3, 6], "m__min_samples_leaf": [5, 20],
                          "m__max_features": [0.3, 0.6]}),
        "GradBoost": (pipe(_prep(scale=False), HistGradientBoostingClassifier(
                         class_weight=cw, random_state=SEED)),
                      {"m__learning_rate": [0.03, 0.1], "m__max_depth": [2, 3],
                       "m__max_iter": [150]}),
        "MLP": (pipe(_prep(), MLPClassifier(max_iter=2000, early_stopping=True, random_state=SEED)),
                {"m__hidden_layer_sizes": [(16,), (32, 16)], "m__alpha": [0.01, 1]}),
    }
    return zoo
