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
~~~~

