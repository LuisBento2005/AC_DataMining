# AC_DataMining

Ice hockey data mining project (Aprendizagem Computacional, FEUP M.EIC).

- [GUIDE.md](GUIDE.md): what we have to do, step by step, and which rubric criterion each part covers.
- [data/](data/): raw CSV tables.

## Setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python src/load_db.py   # builds data/hockey.db (SQLite)
```