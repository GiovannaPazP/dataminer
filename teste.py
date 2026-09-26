import pysus
import pandas as pd


df = pysus.ftp.sih(state="MG", year=2025, month=[1, 2, 3], group="RD", as_dataframe=True)
df.to_parquet("sih_sp_2024_rd.parquet", index=False)


df = pd.read_parquet("sih_sp_2024_rd.parquet")

print(df.shape)
print(df.head())



#df_endo_principal = df[df['DIAG_PRINC'].str.startswith('N80', na=False)]
#diag_cols = [c for c in df.columns if 'DIAG' in c.upper()]
#print(df_endo_principal.shape)
#print(df_endo_principal[['DIAG_PRINC'] + diag_cols + ['PROC_REA']].head(50))

#for coluna in df.columns: print(coluna)

'''
diag_cols = [c for c in df.columns if 'DIAG' in c.upper()]
print(diag_cols)
print(df[diag_cols].head(20))
'''