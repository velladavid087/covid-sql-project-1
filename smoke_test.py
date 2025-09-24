"""
Minimal smoke test for the covid-sql project environment.
Checks: Python, pandas import, and prints first 3 rows of the included CSV if present.
Run: `python smoke_test.py`
"""
import sys
import os

print('Python executable:', sys.executable)
print('Python version:', sys.version)

try:
    import pandas as pd
    print('pandas version:', pd.__version__)
except Exception as e:
    print('Failed to import pandas:', e)
    raise

csvs = [
    'country_wise_latest.csv',
    'covid_19_clean_complete.csv',
    'day_wise.csv',
]
for fname in csvs:
    if os.path.exists(fname):
        print(f"\nReading first 3 rows of {fname}:")
        df = pd.read_csv(fname, nrows=3)
        print(df.head(3).to_string(index=False))
    else:
        print(f"{fname} not found in the repository root.")

print('\nSmoke test completed successfully.')
