#converte .dbc para .parquet

import os
import re
import tempfile
import pandas as pd
import pyreaddbc
from dbfread import DBF


colunas_interesse = [
    'UF_ZI', 'N_AIH', 'CNES', 'SEQ_AIH5', 'ESPEC', 'IDENT', 'CEP', 'MUNIC_RES',
    'MUNIC_MOV', 'NASC', 'SEXO', 'MARCA_UTI', 'DIAR_ACOM', 'PROC_SOLIC', 
    'PROC_REA', 'VAL_TOT', 'DT_INTER', 'DT_SAIDA', 'DIAG_PRINC', 'DIAG_SECUN', 
    'COBRANCA', 'IND_VDRL', 'COD_IDADE', 'IDADE', 'MORTE',
    'DIAS_PERM', 'NACIONAL', 'CAR_INT', 'NUM_FILHOS', 'INSTRU',
    'CONTRACEP1', 'CONTRACEP2', 'GESTRISCO', 'CBOR', 'VINCPREV', 
    'CID_ASSO', 'CID_MORTE', 'RACA_COR', 'ETNIA',
]

PASTA_DBC = "dados_dbc"
PASTA_PARQUET = "dados_atualizados"

os.makedirs(PASTA_PARQUET, exist_ok=True)

def ler_dbc(caminho):
    with tempfile.TemporaryDirectory() as tmp:
        dbf = os.path.join(tmp, "saida.dbf")
        try:
            pyreaddbc.dbc2dbf(caminho, dbf)
        except TypeError:
            pyreaddbc.dbc2dbf(caminho.encode(), dbf.encode())
        return pd.DataFrame(iter(DBF(dbf, encoding="iso-8859-1")))

avisos = {}

for nome in sorted(os.listdir(PASTA_DBC)):
    #pega só os arquivos do formado RDMG seguido de um inteiro de 2 digitos e outro e 
    #terminando em .dbc. Fazemos assim para pegar os grupos de ano (\d{2}) e mês (\d{2})
    m = re.match(r"RDMG(\d{2})(\d{2})\.dbc$", nome, re.IGNORECASE)
    if not m:
        continue
    ano, mes = 2000 + int(m.group(1)), int(m.group(2)) #soma os 2 digitos do ano e atribui os 2 do mes

    try:
        df = ler_dbc(os.path.join(PASTA_DBC, nome))
    except Exception as e:
        print(f"Erro em {ano}-{mes}: {type(e).__name__}: {e}")
        continue

    print(f"{ano}-{mes}: {df.shape}")

    faltantes = [c for c in colunas_interesse if c not in df.columns]
    if faltantes:
        avisos[(ano, mes)] = faltantes

    df = df.reindex(columns=colunas_interesse)
    df['mes'] = mes

    df.to_parquet(f"{PASTA_PARQUET}/sih_mg_{ano}_{mes}.parquet", index=False)

print("\nResumo de colunas ausentes:")
for (ano, mes), cols in avisos.items():
    print(f"{ano}-{mes}: {cols}")