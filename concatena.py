import pandas as pd

anos = range(2022, 2026)
meses = range(1, 13)

PASTA_ORIGEM = "dados"
PASTA_DESTINO = "dados_anos"

for ano in anos:
    dfs = []

    for mes in meses:
        arquivo = f"{PASTA_ORIGEM}/sih_mg_{ano}_{mes}.parquet"

        try:
            df = pd.read_parquet(arquivo)

            if df.empty:
                print(f"VAZIO (0 linhas): {arquivo} -> pulando")
                continue

            df["ano"] = ano
            df["mes"] = mes

            dfs.append(df)

            print(f"OK: {arquivo}")

        except Exception as e:
            print(f"ERRO: {arquivo} -> {e}")

    if dfs:
        df_ano = pd.concat(dfs, ignore_index=True) 
        
        #pega as colunas com mais de um tipo (object) devido as duas formas
        #de baixar e converte para apenas string
        for c in df_ano.select_dtypes(include="object").columns:
            df_ano[c] = df_ano[c].astype("string")

        df_ano.to_parquet(f"{PASTA_DESTINO}/sih_mg_{ano}.parquet", index=False)

        print(f"{ano}: {df_ano.shape}")