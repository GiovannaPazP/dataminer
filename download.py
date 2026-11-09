import argparse
import os
import sys
import time
from ftplib import FTP, all_errors

HOST = "ftp.datasus.gov.br"
UF = "MG"
DIRETORIOS = {
    "novo": "/dissemin/publicos/SIHSUS/200801_/Dados",
    "antigo": "/dissemin/publicos/SIHSUS/199201_200712/Dados",
}
TENTATIVAS = 3


def parse_intervalo(texto):
    if "-" in texto:
        ini, fim = texto.split("-", 1)
        ini, fim = int(ini), int(fim)
        if ini > fim:
            raise ValueError(f"Intervalo invertido: {texto}")
        return list(range(ini, fim + 1))
    return [int(texto)]


def diretorio_do_ano(ano):
    return DIRETORIOS["novo"] if ano >= 2008 else DIRETORIOS["antigo"]


def montar_alvos(tipo, anos, meses):
    alvos = {}
    for ano in anos:
        for mes in meses:
            nome = f"{tipo}{UF}{ano % 100:02d}{mes:02d}.dbc"
            alvos.setdefault(diretorio_do_ano(ano), []).append(nome)
    return alvos


def conectar(diretorio):
    ftp = FTP(HOST, timeout=60)
    ftp.login()
    ftp.set_pasv(True)
    ftp.voidcmd("TYPE I")
    ftp.cwd(diretorio)
    return ftp


def baixar(ftp, nome, destino):
    caminho = os.path.join(destino, nome)
    temporario = caminho + ".part"
    try:
        total = ftp.size(nome)
    except all_errors:
        total = None

    if total is not None and os.path.exists(caminho) and os.path.getsize(caminho) == total:
        return "existente"

    baixado = 0
    with open(temporario, "wb") as f:
        def callback(bloco):
            nonlocal baixado
            f.write(bloco)
            baixado += len(bloco)
            if total:
                print(f"\r{nome}: {baixado / total * 100:5.1f}%", end="", flush=True)

        ftp.retrbinary(f"RETR {nome}", callback, blocksize=64 * 1024)

    os.replace(temporario, caminho)
    print()
    return "baixado"


def processar_diretorio(diretorio, nomes, destino):
    resultado = {"baixado": [], "existente": [], "ausente": [], "falha": []}
    ftp = conectar(diretorio)
    disponiveis = {n.upper(): n for n in ftp.nlst()}

    try:
        for nome in nomes:
            real = disponiveis.get(nome.upper())
            if real is None:
                resultado["ausente"].append(nome)
                continue

            for tentativa in range(1, TENTATIVAS + 1):
                try:
                    status = baixar(ftp, real, destino)
                    resultado[status].append(real)
                    break
                except all_errors as e:
                    print(f"\nErro em {real} (tentativa {tentativa}/{TENTATIVAS}): {e}")
                    try:
                        ftp.close()
                    except Exception:
                        pass
                    time.sleep(3)
                    try:
                        ftp = conectar(diretorio)
                    except all_errors:
                        pass
            else:
                resultado["falha"].append(real)
    finally:
        try:
            ftp.quit()
        except Exception:
            ftp.close()

    return resultado


def main():
    p = argparse.ArgumentParser(description="Download de internações (SIH/SUS) de Minas Gerais")
    p.add_argument("--anos", required=True, help="Ano único ou intervalo. Ex.: 2024 | 2020-2024")
    p.add_argument("--meses", default="1-12", help="Mês único ou intervalo. Ex.: 3 | 1-6 (padrão: 1-12)")
    p.add_argument("--tipo", default="RD", choices=["RD", "RJ", "SP", "ER"], help="RD=AIH reduzida (padrão)")
    p.add_argument("--destino", default="dados_sih_mg")
    args = p.parse_args()

    try:
        anos = parse_intervalo(args.anos)
        meses = parse_intervalo(args.meses)
    except ValueError as e:
        sys.exit(f"Parâmetro inválido: {e}")

    invalidos = [m for m in meses if not 1 <= m <= 12]
    if invalidos:
        sys.exit(f"Meses inválidos: {invalidos}")

    os.makedirs(args.destino, exist_ok=True)
    alvos = montar_alvos(args.tipo, anos, meses)
    total = sum(len(v) for v in alvos.values())
    print(f"{total} arquivo(s) solicitado(s)")

    geral = {"baixado": [], "existente": [], "ausente": [], "falha": []}
    for diretorio, nomes in alvos.items():
        parcial = processar_diretorio(diretorio, nomes, args.destino)
        for chave in geral:
            geral[chave].extend(parcial[chave])

    print(
        f"\nBaixados: {len(geral['baixado'])} | Já existentes: {len(geral['existente'])} | "
        f"Ausentes no servidor: {len(geral['ausente'])} | Falhas: {len(geral['falha'])}"
    )
    if geral["ausente"]:
        print("Ausentes:", ", ".join(geral["ausente"]))
    if geral["falha"]:
        print("Falhas:", ", ".join(geral["falha"]))


if __name__ == "__main__":
    main()
