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

O enriquecimento dos dados do SIH/SUS associa códigos a descrições de diagnósticos, procedimentos, características sociodemográficas e informações geográficas, facilitando a interpretação dos registros e sua utilização nas análises. O processamento segue a documentação da PCDaS e utiliza arquivos auxiliares disponíveis nesta mesma fonte (`ETNIA`, `NACION3D`, `CBO`, `LEITOS` e `TB_SIGTAB`), bem como a malha de municípios do IBGE. Além disso, são criadas variáveis derivadas, como faixas etárias e ano de internação.

| Grupo | Campos e resultados |
|:---|:---|
| **Mapas diretos** | `SEQ_AIH5`, `N_AIH`, `IDENT`, `VINCPREV`, `NUM_FILHOS`, `DIAS_PERM`, `CAR_INT`, `SEXO`, `MARCA_UTI`, `IND_VDRL`, `COD_IDADE`, `MORTE`, `INSTRU`, `CONTRACEP1`, `CONTRACEP2`, `GESTRISCO`, `COMPLEX` e `RACA_COR` geram suas respectivas colunas `def_*`. Os mapas seguem a documentação do SIH/SUS da PCDaS. |
| **CSV de referência** | `ETNIA` → `def_etnia`;<br>`NACIONAL` → `def_nacionalidade` (`NACION3D`);<br>`CBOR` → `def_cbo` (`CBO`);<br>`ESPEC` → `def_leitos` (`LEITOS`);<br>`PROC_REA` e `PROC_SOLIC` → descrições de procedimentos (`TB_SIGTAB`). |
| **Geografia** | `MUNIC_MOV` → `cidade_int`, `estado_int`, `pais_int`;<br>`MUNIC_RES` → `cidade_res`, `estado_res`, `pais_res`.<br>A DTB 2023 fornece os códigos e nomes dos municípios; a UF é derivada dos dois primeiros dígitos do código IBGE e o país é definido como Brasil para os municípios encontrados. |
