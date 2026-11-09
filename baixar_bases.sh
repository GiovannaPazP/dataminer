#!/bin/bash

for ano in {2016..2025}; do
    for mes in {1..12}; do
        python download.py --anos "$ano" --meses "$mes" --destino dados_dbc
    done
done