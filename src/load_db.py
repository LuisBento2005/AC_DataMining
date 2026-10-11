import sqlite3, glob, os
import pandas as pd

con = sqlite3.connect("data/hockey.db")
for f in glob.glob("Data/*.csv"):
    name = os.path.basename(f)[:-4]
    pd.read_csv(f).to_sql(name, con, if_exists="replace", index=False)
    print(name, "ok")
con.close()
