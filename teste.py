import pysus
import pandas as pd


colunas_interesse = [
    'UF_ZI', 'ESPEC', 'IDENT', 'CEP', 'MUNIC_RES', 'NASC', 'SEXO',
    'MARCA_UTI', 'DIAR_ACOM', 'PROC_SOLIC', 'PROC_REA', 'VAL_TOT',
    'DT_INTER', 'DT_SAIDA', 'DIAG_PRINC', 'DIAG_SECUN', 'COBRANCA',
    'IND_VDRL', 'MUNIC_MOV', 'COD_IDADE', 'IDADE', 'MORTE', 'DIAS_PERM',
    'NACIONAL', 'CAR_INT', 'NUM_FILHOS', 'INSTRU', 'CID_NOTIF',
    'CONTRACEP1', 'CONTRACEP2', 'GESTRISCO', 'CBOR', 'VINCPREV',
    'INFEHOSP', 'CID_ASSO', 'CID_MORTE', 'RACA_COR', 'ETNIA',
    'DIAGSEC1', 'DIAGSEC2', 'DIAGSEC3', 'DIAGSEC4', 'DIAGSEC5',
    'DIAGSEC6', 'DIAGSEC7', 'DIAGSEC8', 'DIAGSEC9',
    'TPDISEC1', 'TPDISEC2', 'TPDISEC3', 'TPDISEC4', 'TPDISEC5',
    'TPDISEC6', 'TPDISEC7', 'TPDISEC8', 'TPDISEC9',
]

#df = pysus.ftp.sih(state="MG", year=2025, month=[1, 2, 3], group="RD", as_dataframe=True)
#df.to_parquet("sih_rd_2024_rd.parquet", index=False)


df = pd.read_parquet("sih_mg_2025_3_control.parquet")

print(df.shape)
'''print(df.head())

df = df.reindex(columns=colunas_interesse)
print(df.shape, df.head())'''
print(df['DIAGSEC1'].isna().sum())
print(df['DIAGSEC1'].sample(20).to_list())
print((df['DIAGSEC1'] == '').sum())


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