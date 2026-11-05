# AC_DataMining

Ice hockey data mining project (Aprendizagem Computacional, FEUP M.EIC).

- [GUIDE.md](GUIDE.md): what we have to do, step by step, and which rubric criterion each part covers.
- [docs/GUIAO.md](docs/GUIAO.md): explanation (in Portuguese) of everything that was built and how to present it.
- [data/](data/): raw CSV tables.

## Setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python src/load_db.py   # builds data/hockey.db (SQLite)
```

## Reproduce the results

Run the notebooks in order (from `notebooks/`):

| Notebook | CRISP-DM phase | Output |
|---|---|---|
| `01_eda.ipynb` | Data understanding | plots, findings |
| `02_statistical_analysis.ipynb` | Data understanding | PCA, clustering, tests |
| `03_data_preparation.ipynb` | Data preparation | `data/processed/features.csv`, `feature_lists.json` |
| `04_task_a_ranking.ipynb` | Modelling + evaluation, task (a) | `data/processed/results/task_a_*` (≈ 5 min) |
| `05_task_b_coach_change.ipynb` | Modelling + evaluation, task (b) | `data/processed/results/task_b_*` (≈ 15 min) |

Or, non-interactively: `cd notebooks && jupyter nbconvert --to notebook --execute --inplace 03_*.ipynb 04_*.ipynb 05_*.ipynb`.

## Code layout

| Path | Content |
|---|---|
| `sql/` | SQL used for integration, aggregation and quality checks (SQLite) |
| `src/load_db.py` | CSV → SQLite |
| `src/features.py` | builds the leak-free dataset (one row per franchise-season) |
| `src/validation.py` | walk-forward splits, metrics, Friedman/Nemenyi, Winsorizer, feature selector |
| `src/models.py` | the 8 algorithms per task, as pipelines with their parameter grids |
| `src/experiment.py` | runs the models through walk-forward with inner temporal tuning |
