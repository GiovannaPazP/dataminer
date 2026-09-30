import pysus
import pandas as pd
import os

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

anos = range(2016,2026) #10 anos
mes = list(range(1,13))

os.makedirs("dados", exist_ok=True)

avisos = {}

for ano in anos:
    print(f"Baixando tabela {ano}...")

    try:
        df = pysus.ftp.sih(state="MG", year=ano, month=mes, group="RD", as_dataframe=True)
    except Exception as e:
        print(f"Erro no ano {ano}: {e}")
        continue

    #checagem para ver se tem coluna faltante
    faltantes = [c for c in colunas_interesse if c not in df.columns]
    if faltantes:
        aviso[ano] = faltantes

    #reindex garante que se alguma coluna não existe
    #naquele ano ela entra como nan ao inves de quebrar o script
    df = df.reindex(columns=colunas_interesse)
    df['ano'] = ano

    df.to_parquet(f"dados/sih_mg_{ano}.parquet", index=False)
    print(f"\n\n\t  {ano}: {df.shape}")

print("\nResumo de colunas ausentes por ano:")
for ano, col in avisos.items():
    print(f"{ano}: {col}")