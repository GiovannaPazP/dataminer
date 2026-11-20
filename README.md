# Instalação do ambiente:
```bash
  conda env create -f environment.yml
```

# Para controle e testes
sih_mg_2025_3_control.parquet


# Organização 
```text
projeto/
├── dados_dbc/
├── dados_parquet/
├── dados_anos/
├── dados_enriquecidos/
├── baixar_bases.sh
├── download.py
├── converte.py
├── concatena.py
├── environment.yml
└── README.md
```


# Base

## Download das bases
Para realizar o download dos arquivos DBC do SIH/SUS referentes ao período de 2016 a 2025, execute:
```bash
  bash baixar_bases.sh 
```

Os arquivos serão armazenados no diretório `dados_dbc`.

## Conversão
Os dados são .dbc, para trabalhar com um formato mais leve convertemos para .parquet com:
```bash
  python converte.py
```

Os arquivos serão armazenados em `dados_parquet`.

## Concatenação
Os dados vêm em meses, para trabalharmos com os anos completos é necessário concatenar as bases com:
```bash
  python concatena.py
```

Os dados serão armazenados em `dados_anos`.


# Enriquecimento

O enriquecimento dos dados do SIH/SUS associa códigos a descrições de diagnósticos, procedimentos, características sociodemográficas e informações geográficas, facilitando a interpretação dos registros e sua utilização nas análises. O processamento segue a documentação da PCDaS e utiliza arquivos auxiliares disponíveis nesta mesma fonte, bem como a malha de municípios do IBGE. Além disso, são criadas variáveis derivadas, como faixas etárias e ano de internação.

### Correspondência entre colunas e colunas geradas

| Coluna(s) de origem | Coluna(s) gerada(s) |
|---|---|
| `SEQ_AIH5`, `N_AIH`, `IDENT`, `VINCPREV`, `NUM_FILHOS`, `DIAS_PERM`, `CAR_INT`, `SEXO`, `MARCA_UTI`, `IND_VDRL`, `COD_IDADE`, `MORTE`, `INSTRU`, `CONTRACEP1`, `CONTRACEP2`, `GESTRISCO`, `COMPLEX`, `RACA_COR` | Respectivas colunas `def_*` |
| `ETNIA` | `def_etnia` |
| `NACIONAL` | `def_nacionalidade` |
| `CBOR` | `def_cbo` |
| `ESPEC` | `def_leitos` |
| `PROC_REA`, `PROC_SOLIC` | Descrições dos procedimentos (tabela `TB_SIGTAB`) |
| `MUNIC_MOV` | `cidade_int`, `estado_int`, `pais_int` |
| `MUNIC_RES` | `cidade_res`, `estado_res`, `pais_res` |
~~~~

