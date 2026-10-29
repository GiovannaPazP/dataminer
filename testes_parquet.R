# Dependências: dplyr manipula tabelas, Arrow lê/grava Parquet e readxl lê a DTB.
# Os pacotes precisam estar instalados antes de executar este script.
library(dplyr)
library(arrow)
library(readxl)

 
# TESTES COMPLETOS DO ENRIQUECIMENTO SIH/SUS - PARQUET
# VERSÃO DE BAIXO CONSUMO DE MEMÓRIA
 

# CONFIGURAÇÃO DOS NOMES: altere os mesmos valores nos dois scripts.
# Estado, ano e meses apenas identificam a saída; todas as linhas são testadas.
# Estes valores formam o identificador dos arquivos. Eles NÃO filtram registros.
# Altere também os caminhos quando trocar o arquivo bruto utilizado.
ESTADO <- "MG"
ANO <- 2016L
MES_INICIAL <- 1L
MES_FINAL <- 12L
# Siglas válidas das UFs e seus códigos. Aqui a tabela valida a configuração.
uf_codigos <- c(RO="11", AC="12", AM="13", RR="14", PA="15", AP="16", TO="17",
 MA="21", PI="22", CE="23", RN="24", PB="25", PE="26", AL="27", SE="28", BA="29",
 MG="31", ES="32", RJ="33", SP="35", PR="41", SC="42", RS="43", MS="50", MT="51", GO="52", DF="53")
ESTADO <- toupper(trimws(ESTADO))
# Interrompe a execução se a configuração contiver UF, ano ou meses inválidos.
stopifnot(length(ESTADO)==1L, ESTADO %in% names(uf_codigos),
 length(ANO)==1L, !is.na(ANO), ANO==as.integer(ANO), ANO>=1900L,
 MES_INICIAL %in% 1:12, MES_FINAL %in% 1:12, MES_INICIAL<=MES_FINAL)
# Exemplo do identificador gerado: MG_2016_1_12.
identificador <- paste(ESTADO, ANO, MES_INICIAL, MES_FINAL, sep="_")
# Diretório principal. Os demais caminhos são montados a partir dele.
pasta_sih <- "/home/goddess/Documents/dados_sus/sihsus"
pasta_parquet <- file.path(pasta_sih, "enriquecimento", "parquet")
pasta_anos <- file.path(pasta_sih, "dados_anos")
# Use exatamente o mesmo arquivo de entrada do enriquecimento.
# Arquivo bruto efetivamente utilizado. Deve ser o mesmo nos dois scripts.
# Trocar apenas ESTADO/ANO/MESES não muda automaticamente este nome de arquivo.
caminho_entrada <- file.path(pasta_anos, "sih_mg_2016.parquet")
pasta_enriquecidos <- file.path(pasta_parquet, "dados enriquecidos")
pasta_aux <- file.path(pasta_sih, "bases_auxiliares")
pasta_dtb <- file.path(pasta_sih, "DTB_2023", "DTB_2023")
pasta_cid <- file.path(pasta_sih, "TABCIH", "TAB_CIH")
caminho_dados <- file.path(pasta_enriquecidos, paste0("dados_enriquecidos_", identificador))
pasta_saida <- file.path(pasta_parquet, "resultado dos testes")
dir.create(pasta_saida, recursive=TRUE, showWarnings=FALSE)
arquivo_resumo <- file.path(pasta_saida, paste0("resultado dos testes_", identificador, ".csv"))

cat("Abrindo Parquet sem carregar a base inteira...\n")
dataset <- arrow::open_dataset(caminho_dados, format="parquet")
cat("Dataset aberto com sucesso.\n\n")
if (!file.exists(caminho_entrada)) stop("Arquivo original não encontrado: ", caminho_entrada)
# A entrada bruta é aberta separadamente para conferir estrutura e total de linhas.
# Verifique este caminho ao alternar entre versões da base.
dataset_original <- arrow::open_dataset(caminho_entrada, format="parquet")
colunas_originais <- names(dataset_original)




# Guarda resumos acumulados, e não uma cópia de todas as linhas testadas.
resultados <- list(data.frame(teste=character(), status=character(), n=numeric()))
# Acrescenta o resumo de um teste à lista do lote atual. <<- atualiza essa lista
# no ambiente externo à função; a lista é reiniciada a cada lote.
adicionar_resultado <- function(x) {
  resultados_lote[[length(resultados_lote) + 1L]] <<- x
}

# Converte códigos para texto, remove espaços nas extremidades e trata vazio como NA.
# Não remove zeros à esquerda dos códigos que já foram lidos como texto.
normalizar_codigo <- function(x) {
  x <- trimws(as.character(x)); x[x == ""] <- NA_character_; x
}

# Recalcula a descrição esperada pelas regras dos mapas para compará-la ao resultado.
decodificar <- function(coluna, mapa) {
  r <- unname(mapa[as.character(coluna)])
  r[is.na(r)] <- ""
  r
}

# Normalização usada apenas na consulta: preserva o valor original da base.
# Zero(s), vazio e NA não são códigos CID a procurar nas referências.
# Prepara uma cópia do CID para a consulta: maiúsculas, sem ponto e sem zeros isolados.
# Essa normalização não substitui os códigos CID originais da base.
normalizar_cid <- function(x) {
  x <- toupper(gsub(".", "", normalizar_codigo(x), fixed=TRUE))
  x[!is.na(x) & grepl("^0+$", x)] <- NA_character_
  x
}

# Lê um CSV de referência separado por ponto e vírgula. As colunas são texto
# para preservar zeros à esquerda. Uma linha por código evita multiplicação nos joins.
ler_auxiliar <- function(nome) {
  read.csv(file.path(pasta_aux,paste0(nome,".csv")), sep=";", stringsAsFactors=FALSE,
           colClasses="character", check.names=FALSE) %>%
    transmute(cod=normalizar_codigo(cod),value=trimws(as.character(value))) %>%
    distinct(cod,.keep_all=TRUE)
}

# Conta quantas linhas receberam cada status. n representa registros por teste,
# não pacientes únicos. Não some n entre testes diferentes como se fossem pessoas.
resumir_status <- function(nome, status) {
  as.data.frame(table(status), stringsAsFactors=FALSE) %>%
    rename(status=status,n=Freq) %>%
    mutate(teste=nome,.before=1)
}

# Confere a estrutura antes de selecionar as colunas. A ausência da coluna
# original impede a comparação, mesmo se o enriquecimento criou def_* com NA.
# n conta as linhas do lote cuja comparação não pôde ser realizada.
# Evita selecionar campos inexistentes. Consulta a estrutura da entrada para
# distinguir ausência original de coluna perdida na saída. Isso não compara valores linha a linha.
verificar_colunas_teste <- function(nome, original, enriquecida) {
  tem_original <- original %in% names(dataset)
  tem_enriquecida <- enriquecida %in% names(dataset)
  if (tem_original && tem_enriquecida) return(TRUE)

  status <- if (!tem_original && !tem_enriquecida) {
    if (original %in% colunas_originais) "COLUNA PERDIDA NO ENRIQUECIMENTO" else "AUSENTE NA BASE ORIGINAL"
  } else if (!tem_original) {
    if (original %in% colunas_originais) "COLUNA PERDIDA NO ENRIQUECIMENTO" else "AUSENTE NA BASE ORIGINAL"
  } else {
    "COLUNA ENRIQUECIDA AUSENTE"
  }

  adicionar_resultado(data.frame(
    teste=nome, status=status, n=nrow(dataset), stringsAsFactors=FALSE
  ))
  if (numero_lote == 1L) {
    faltantes <- setdiff(c(original, enriquecida), names(dataset))
    cat("[AVISO]", nome, "- comparação não realizada; faltam:",
        paste(faltantes, collapse=", "), "\n")
  }
  FALSE
}

# Confere a descrição calculada por um mapa contra a descrição no lote enriquecido.
# OK significa concordância com essa regra; não prova validade clínica do dado original.
testar_mapa <- function(nome, original, enriquecida, mapa) {
  if (!verificar_colunas_teste(nome, original, enriquecida)) return(invisible(NULL))
  x <- dataset %>% select(all_of(c(original,enriquecida)))
  esperado <- decodificar(x[[original]],mapa)
  obtido <- as.character(x[[enriquecida]]); obtido[is.na(obtido)] <- ""
  r <- resumir_status(nome,ifelse(esperado==obtido,"OK","DIVERGENTE"))
  adicionar_resultado(r); rm(x,esperado,obtido,r)
}

# Reconsulta o CSV auxiliar pelo código original e compara a descrição obtida.
# Distingue código ausente, código sem referência, descrição vazia e divergência.
testar_aux <- function(nome, original, enriquecida, tabela, nao_informado_na=FALSE) {
  if (!verificar_colunas_teste(nome, original, enriquecida)) return(invisible(NULL))
  x <- dataset %>% select(all_of(c(original,enriquecida))) %>%
    transmute(codigo=normalizar_codigo(.data[[original]]),obtido=normalizar_codigo(.data[[enriquecida]])) %>%
    left_join(tabela %>% transmute(codigo=normalizar_codigo(cod),esperado=normalizar_codigo(value)),by="codigo")
  if (nao_informado_na) x$esperado[x$esperado=="NÃO INFORMADO"] <- NA_character_
  status <- case_when(
    is.na(x$codigo)~"SEM CÓDIGO",
    original == "ETNIA" & x$codigo == "0000" & is.na(x$esperado) & is.na(x$obtido) ~ "CÓDIGO NÃO INFORMADO",
    original == "ETNIA" & x$codigo == "0000" & is.na(x$esperado) & !is.na(x$obtido) ~ "DIVERGENTE",
    is.na(x$esperado)~"CÓDIGO NÃO ENCONTRADO",
                      is.na(x$obtido)~"VALOR NÃO PREENCHIDO",x$obtido==x$esperado~"OK",TRUE~"DIVERGENTE")
  adicionar_resultado(resumir_status(nome,status)); rm(x,status)
}

 
# MAPAS DAS DECODIFICAÇÕES DIRETAS
 
mapa_ident <- c("1"="Normal","5"="Longa permanência","0"="","9"="")
mapa_vincprev <- c("1"="Autônomo","2"="Desempregado","3"="Aposentado","4"="Não segurado","5"="Empregado","6"="Empregador")
mapa_num_filhos <- c("0"="Sem filhos/Não inform","1"="1 filho","2"="2 filhos","3"="3 filhos","4"="4 a 5 filhos","5"="4 a 5 filhos","6"="6 a 9 filhos","7"="6 a 9 filhos","8"="6 a 9 filhos","9"="6 a 9 filhos","10"="10 filhos ou mais","99"="10 filhos ou mais")
mapa_dias_perm <- c("0000"="0 dias","0001"="1 dia","0002"="2 dias","0003"="3 dias","0004"="4 dias","0005"="5 dias","0006"="6 dias","0007"="7 dias","0014"="8-14 dias","0021"="15-21 dias","0028"="22-28 dias","9999"="29 dias e +")
mapa_car_int <- c("1"="Eletivo","2"="Urgência","3"="Acidente no local trabalho ou a serv da empresa","4"="Acidente no trajeto para o trabalho","5"="Outros tipo de acidente de trânsito","6"="Out tp lesões e envenen por agent quím físicos")
mapa_sexo <- c("1"="Masculino","2"="Feminino","3"="Feminino","0"="","9"="")
mapa_marca_uti <- c("00"="Não utilizou UTI","74"="UTI adulto - tipo I","75"="UTI adulto - tipo II","76"="UTI adulto - tipo III","77"="UTI infantil - tipo I","78"="UTI infantil - tipo II","79"="UTI infantil - tipo III","80"="UTI neonatal - tipo I","81"="UTI neonatal - tipo II","82"="UTI neonatal - tipo III","83"="UTI de queimados","85"="UTI coronariana tipo II - UCO tipo II","86"="UTI coronariana tipo III - UCO tipo III","99"="UTI Doador","01"="Utilizou mais de um tipo de UTI")
mapa_sim_nao <- c("0"="Não","1"="Sim")
mapa_cod_idade <- c("2"="Dias","3"="Meses","4"="Anos","0"="")
mapa_morte <- c("0"="Sem óbito","1"="Com óbito")
mapa_instru <- c("1"="Analfabeto","2"="1º grau","3"="2º grau","4"="3º grau","0"="","9"="")
mapa_contracep <- c("01"="LAM","02"="Ogino Kaus","03"="Temperatura basal","04"="Billings","05"="Cinto térmico","06"="DIU","07"="Diafragma","08"="Preservativo","09"="Espermicida","10"="Hormônio oral","11"="Hormônio injetável","12"="Coito interrompido","00"="","99"="")
mapa_raca_cor <- c("01"="Branca","02"="Preta","03"="Parda","04"="Amarela","05"="Indígena","99"="Sem Informação")

# Referências carregadas somente uma vez, antes de percorrer os lotes.
cat("[PREPARAÇÃO] Carregando referências dos testes...\n")
mapa_uf <- c("11"="Rondônia","12"="Acre","13"="Amazonas","14"="Roraima","15"="Pará","16"="Amapá","17"="Tocantins","21"="Maranhão","22"="Piauí","23"="Ceará","24"="Rio Grande do Norte","25"="Paraíba","26"="Pernambuco","27"="Alagoas","28"="Sergipe","29"="Bahia","31"="Minas Gerais","32"="Espírito Santo","33"="Rio de Janeiro","35"="São Paulo","41"="Paraná","42"="Santa Catarina","43"="Rio Grande do Sul","50"="Mato Grosso do Sul","51"="Mato Grosso","52"="Goiás","53"="Distrito Federal")
municipios <- readxl::read_excel(file.path(pasta_dtb,"RELATORIO_DTB_BRASIL_MUNICIPIO.xls"),skip=6,col_types="text") %>%
  transmute(codigo_ibge=normalizar_codigo(`Código Município Completo`),cidade=trimws(as.character(`Nome_Município`))) %>%
  filter(!is.na(codigo_ibge),!is.na(cidade)) %>% mutate(cod=substr(codigo_ibge,1,6),estado=unname(mapa_uf[substr(codigo_ibge,1,2)]),pais="Brasil") %>% distinct(cod,.keep_all=TRUE)
ETNIA_aux <- ler_auxiliar("ETNIA")
NACION3D_aux <- ler_auxiliar("NACION3D")
CBO_aux <- ler_auxiliar("CBO")
LEITOS_aux <- ler_auxiliar("LEITOS")
SIGTAP <- ler_auxiliar("TB_SIGTAB")

# Referências CID-10 usadas para conferir as descrições.
# Usa outro método de leitura dos CNV: separa o último token como código.
# Assim, os testes não repetem a mesma expressão regular completa do enriquecimento.
# Ainda dependem das mesmas tabelas de referência, que podem ter limitações.
ler_cnv_teste <- function(arquivo, intervalos=FALSE) {
  linhas <- readLines(file.path(pasta_cid,arquivo),encoding="latin1",warn=FALSE)
  linhas <- linhas[-1L]
  linhas <- linhas[nzchar(trimws(linhas))]
  if (!length(linhas)) stop("CNV sem linhas de dados: ", arquivo)
  extrair <- function(linha) {
    linha <- trimws(sub(",\\s*$", "", linha))
    partes_linha <- strsplit(linha, "[[:space:]]+")[[1L]]
    codigo <- tail(partes_linha, 1L)
    if (!grepl("^[A-Z][0-9]{2}(?:[A-Z0-9.]*)?(?:-[A-Z][0-9]{2})?$",
               codigo, perl=TRUE)) return(c(NA_character_, NA_character_))
    # Retira o último token (código) e o primeiro token (número da linha).
    descricao <- trimws(sub("[[:space:]]+[^[:space:]]+$", "", linha))
    descricao <- trimws(sub("^[0-9]+[[:space:]]+", "", descricao))
    c(codigo, descricao)
  }
  partes <- t(vapply(linhas,extrair,character(2)))
  tabela <- data.frame(cod=partes[,1],value=partes[,2],stringsAsFactors=FALSE)
  if(intervalos) {
    tabela <- tabela[!is.na(tabela$cod) & grepl("^[A-Z][0-9]{2}-[A-Z][0-9]{2}$",tabela$cod),,drop=FALSE]
    tabela$inicio <- substr(tabela$cod,1,3)
    tabela$fim <- substr(tabela$cod,5,7)
  } else {
    tabela$cod <- gsub("\\.","",tabela$cod)
    tabela <- tabela[!is.na(tabela$cod) & grepl("^[A-Z][0-9]{2}[A-Z0-9]?$",tabela$cod),,drop=FALSE]
  }
  tabela <- tabela[!is.na(tabela$value) & nzchar(tabela$value),,drop=FALSE]
  tabela <- tabela[!duplicated(tabela$cod),,drop=FALSE]
  if (!nrow(tabela)) stop("Nenhuma referência CID lida em: ", arquivo)
  tabela
}
mapear_intervalos_teste <- function(codigos,tabela) {
  x <- substr(normalizar_codigo(codigos),1,3)
  saida <- rep(NA_character_,length(x))
  for(i in seq_len(nrow(tabela))) {
    ok <- !is.na(x) & x>=tabela$inicio[i] & x<=tabela$fim[i] & is.na(saida)
    saida[ok] <- tabela$value[i]
  }
  saida
}
cid_capitulos_teste <- ler_cnv_teste("CID10CAP.CNV",TRUE)
cid_grupos_teste <- ler_cnv_teste("CID10GRUPO.CNV",TRUE)
cid_categorias_teste <- ler_cnv_teste("CID10_3D.CNV")
cid_subcategorias_teste <- dplyr::bind_rows(lapply(sprintf("CID10_%02d.CNV",1:22),ler_cnv_teste))
cid_subcategorias_teste <- cid_subcategorias_teste[!duplicated(cid_subcategorias_teste$cod),,drop=FALSE]
categorias_mapa_teste <- setNames(cid_categorias_teste$value,cid_categorias_teste$cod)
subcategorias_mapa_teste <- setNames(cid_subcategorias_teste$value,cid_subcategorias_teste$cod)

cat("[PREPARAÇÃO] Contando linhas para exibir o progresso...\n")
# Arrow calcula o total; collect() traz apenas a contagem, não a base inteira.
total_linhas <- dataset %>% summarise(total=n()) %>% collect()
total_linhas <- as.numeric(total_linhas$total[[1L]])
if (total_linhas == 0) stop("O dataset enriquecido está vazio.")
contagem_original <- dataset_original %>% summarise(total=n()) %>% collect()
total_original <- as.numeric(contagem_original$total[[1L]])
# Compara quantidade de linhas e presença de colunas entre entrada e saída.
# Totais iguais não garantem igualdade de todos os registros.
resultados_estrutura <- data.frame(
  teste="Contagem de linhas: entrada e saída",
  status=if (total_original == total_linhas) "OK" else "DIVERGENTE",
  n=total_linhas, stringsAsFactors=FALSE
)
cat(sprintf("[ESTRUTURA] Entrada: %.0f linhas; saída: %.0f linhas.\n", total_original, total_linhas))
campos_estrutura <- c("DIAG_PRINC", "DIAG_SECUN", "CID_ASSO", "CID_MORTE")
for (campo in campos_estrutura) {
  na_entrada <- campo %in% colunas_originais
  na_saida <- campo %in% names(dataset)
  status_estrutura <- if (!na_entrada && !na_saida) "AUSENTE NA BASE ORIGINAL" else
    if (na_entrada && !na_saida) "COLUNA PERDIDA NO ENRIQUECIMENTO" else
    if (!na_entrada && na_saida) "COLUNA CRIADA SEM ORIGEM" else "OK"
  resultados_estrutura <- bind_rows(resultados_estrutura, data.frame(
    teste=paste("Estrutura ->",campo), status=status_estrutura, n=total_linhas
  ))
}
# Esta seção verifica presença de colunas e quantidade de linhas, não igualdade
# dos valores linha a linha entre os dois arquivos.
rm(dataset_original)

linhas_testadas <- 0
numero_lote <- 0L
inicio <- Sys.time()
cat(sprintf("[INÍCIO] %.0f linhas para testar.\n", total_linhas))

# Executa todos os testes sobre o data.frame do lote atual.
dataset_completo <- dataset
# Os testes percorrem o dataset uma vez, em lotes de até 5.000 linhas.
scanner_testes <- arrow::Scanner$create(dataset_completo, batch_size=5000L)
reader_testes <- scanner_testes$ToRecordBatchReader()
repeat {
  lote <- reader_testes$read_next_batch()
  if (is.null(lote)) break
  # A partir daqui, as funções de teste trabalham somente com este lote em memória.
  dataset <- as.data.frame(lote)
  numero_lote <- numero_lote + 1L
  resultados_lote <- list()
  cat(sprintf("[LOTE %d] Testando %d linhas...\n", numero_lote, nrow(dataset)))
 
# 1. DECODIFICAÇÕES DIRETAS
 
testar_mapa("IDENT -> def_ident","IDENT","def_ident",mapa_ident)
testar_mapa("VINCPREV -> def_vincprev","VINCPREV","def_vincprev",mapa_vincprev)
testar_mapa("NUM_FILHOS -> def_num_filhos","NUM_FILHOS","def_num_filhos",mapa_num_filhos)
testar_mapa("DIAS_PERM -> def_dias_perm","DIAS_PERM","def_dias_perm",mapa_dias_perm)
testar_mapa("CAR_INT -> def_car_int","CAR_INT","def_car_int",mapa_car_int)
testar_mapa("SEXO -> def_sexo","SEXO","def_sexo",mapa_sexo)
testar_mapa("MARCA_UTI -> def_marca_uti","MARCA_UTI","def_marca_uti",mapa_marca_uti)
testar_mapa("IND_VDRL -> def_ind_vdrl","IND_VDRL","def_ind_vdrl",mapa_sim_nao)
testar_mapa("COD_IDADE -> def_cod_idade","COD_IDADE","def_cod_idade",mapa_cod_idade)
testar_mapa("MORTE -> def_morte","MORTE","def_morte",mapa_morte)
testar_mapa("INSTRU -> def_instru","INSTRU","def_instru",mapa_instru)
testar_mapa("CONTRACEP1 -> def_contracep1","CONTRACEP1","def_contracep1",mapa_contracep)
testar_mapa("CONTRACEP2 -> def_contracep2","CONTRACEP2","def_contracep2",mapa_contracep)
testar_mapa("GESTRISCO -> def_gestrisco","GESTRISCO","def_gestrisco",mapa_sim_nao)
testar_mapa("RACA_COR -> def_raca_cor","RACA_COR","def_raca_cor",mapa_raca_cor)

 
# 3. MUNICÍPIOS
 
testar_aux("MUNIC_MOV -> cidade_int","MUNIC_MOV","cidade_int",municipios %>% transmute(cod,value=cidade))
testar_aux("MUNIC_MOV -> estado_int","MUNIC_MOV","estado_int",municipios %>% transmute(cod,value=estado))
testar_aux("MUNIC_MOV -> pais_int","MUNIC_MOV","pais_int",municipios %>% transmute(cod,value=pais))
testar_aux("MUNIC_RES -> cidade_res","MUNIC_RES","cidade_res",municipios %>% transmute(cod,value=cidade))
testar_aux("MUNIC_RES -> estado_res","MUNIC_RES","estado_res",municipios %>% transmute(cod,value=estado))
testar_aux("MUNIC_RES -> pais_res","MUNIC_RES","pais_res",municipios %>% transmute(cod,value=pais))

 
# 4. TABELAS AUXILIARES
 
testar_aux("ETNIA -> def_etnia","ETNIA","def_etnia",ETNIA_aux,TRUE)
testar_aux("NACIONAL -> def_nacionalidade","NACIONAL","def_nacionalidade",NACION3D_aux)
testar_aux("CBOR -> def_cbo","CBOR","def_cbo",CBO_aux)
testar_aux("ESPEC -> def_leitos","ESPEC","def_leitos",LEITOS_aux)
testar_aux("PROC_REA -> def_procedimento_realizado","PROC_REA","def_procedimento_realizado",SIGTAP)
testar_aux("PROC_SOLIC -> def_procedimento_solicitado","PROC_SOLIC","def_procedimento_solicitado",SIGTAP)

 
# 5. DATAS E FAIXAS ETÁRIAS
 
x <- dataset %>% select(DT_INTER,DT_SAIDA,dt_inter,dt_saida,ano_internacao,dia_semana_internacao,ano_saida,dia_semana_saida,IDADE,COD_IDADE,def_idade_anos,def_idade_bas,def_idade_pub,def_idade_18)
dti <- as.Date(as.character(x$DT_INTER),format="%Y%m%d"); dts <- as.Date(as.character(x$DT_SAIDA),format="%Y%m%d")
idade <- suppressWarnings(as.numeric(x$IDADE)); codidade <- suppressWarnings(as.numeric(x$COD_IDADE)); idadeanos <- ifelse(is.na(idade)|is.na(codidade),NA_real_,ifelse(codidade<4,0,idade))
comparar <- function(nome,esp,obt){ ok <- (is.na(esp)&is.na(obt))|(!is.na(esp)&!is.na(obt)&as.character(esp)==as.character(obt)); adicionar_resultado(resumir_status(nome,ifelse(ok,"OK","DIVERGENTE"))) }
comparar("DT_INTER -> dt_inter",dti,as.Date(x$dt_inter))
comparar("DT_SAIDA -> dt_saida",dts,as.Date(x$dt_saida))
comparar("dt_inter -> ano_internacao",as.integer(format(dti,"%Y")),x$ano_internacao)
comparar("dt_inter -> dia_semana_internacao",weekdays(dti),x$dia_semana_internacao)
comparar("dt_saida -> ano_saida",as.integer(format(dts,"%Y")),x$ano_saida)
comparar("dt_saida -> dia_semana_saida",weekdays(dts),x$dia_semana_saida)
comparar("IDADE/COD_IDADE -> def_idade_anos",idadeanos,x$def_idade_anos)
bas <- case_when(is.na(idadeanos)~NA_character_,idadeanos<1~"<1a",idadeanos<5~"1-4a",idadeanos<15~"5-14a",idadeanos<50~"15-49a",TRUE~"50e+a")
pub <- case_when(is.na(idadeanos)~NA_character_,idadeanos<1~"<1a",idadeanos<5~"1-4a",idadeanos<15~"5-14a",idadeanos<25~"15-24a",idadeanos<35~"25-34a",idadeanos<45~"35-44a",idadeanos<55~"45-54a",idadeanos<65~"55-64a",TRUE~"65e+a")
f18 <- case_when(is.na(idadeanos)~NA_character_,idadeanos<1~"<1a",idadeanos<5~"1-4a",idadeanos<10~"5-9a",idadeanos<15~"10-14a",idadeanos<20~"15-19a",idadeanos<25~"20-24a",idadeanos<30~"25-29a",idadeanos<35~"30-34a",idadeanos<40~"35-39a",idadeanos<45~"40-44a",idadeanos<50~"45-49a",idadeanos<55~"50-54a",idadeanos<60~"55-59a",idadeanos<65~"60-64a",idadeanos<70~"65-69a",idadeanos<75~"70-74a",idadeanos<80~"75-79a",TRUE~"80e+a")
comparar("def_idade_anos -> def_idade_bas",bas,x$def_idade_bas); comparar("def_idade_anos -> def_idade_pub",pub,x$def_idade_pub); comparar("def_idade_anos -> def_idade_18",f18,x$def_idade_18)
rm(x,dti,dts,idade,codidade,idadeanos,bas,pub,f18)

 
# 6. CID-10 - TESTES INDEPENDENTES DE CORRESPONDENCIA
 
# Lê as referências com a mesma estrutura CNV, mas valida cada campo
# com outro método de leitura. A estrutura de entrada e saída é conferida acima.
# Apenas os campos CID mantidos são avaliados. Para cada um, as quatro descrições
# são verificadas separadamente, mantendo a distinção entre categoria e subcategoria.
campos_cid <- c("DIAG_PRINC", "DIAG_SECUN", "CID_ASSO", "CID_MORTE")
for (campo in campos_cid) {
  if (!campo %in% names(dataset)) next
  prefixo <- if (campo == "DIAG_PRINC") "def_diag_princ" else
    if (campo == "DIAG_SECUN") "def_diag_secun" else paste0("def_",tolower(campo))
  codigo <- normalizar_cid(dataset[[campo]])
  categoria <- substr(codigo,1,3)
  for (sufixo in c("cap","grupo","cat","subcat")) {
    coluna <- paste0(prefixo,"_",sufixo)
    nome_teste <- paste(campo,"->",coluna)
    if (!coluna %in% names(dataset)) {
      adicionar_resultado(data.frame(teste=nome_teste,status="COLUNA AUSENTE",n=nrow(dataset)))
      next
    }
    esperado <- switch(sufixo,
      cap=mapear_intervalos_teste(categoria,cid_capitulos_teste),
      grupo=mapear_intervalos_teste(categoria,cid_grupos_teste),
      cat=unname(categorias_mapa_teste[categoria]),
      subcat=unname(subcategorias_mapa_teste[codigo]))
    obtido <- normalizar_codigo(dataset[[coluna]])
    formato_cid <- !is.na(codigo) & grepl("^[A-Z][0-9]{2}[A-Z0-9]?$", codigo)
    categoria_conhecida <- !is.na(codigo) & nchar(codigo)==3L &
      codigo %in% names(categorias_mapa_teste)
    # A ausência de subcategoria não apaga a descrição da categoria.
    # Classifica cada linha: ausência de código, falta de referência e divergência
    # são situações diferentes. Categoria sem subcategoria não equivale a diagnóstico ausente.
    status <- case_when(
      is.na(codigo) & is.na(obtido) ~ "SEM CÓDIGO INFORMADO",
      is.na(codigo) & !is.na(obtido) ~ "DIVERGENTE",
      !formato_cid ~ "FORMATO DE CID NÃO RECONHECIDO",
      is.na(esperado) & !is.na(obtido) ~ "DIVERGENTE",
      sufixo == "subcat" & categoria_conhecida & is.na(esperado) ~ "CATEGORIA SEM SUBCATEGORIA NA REFERÊNCIA",
      is.na(esperado) ~ "SEM REFERÊNCIA",
      is.na(obtido) ~ "VALOR NÃO PREENCHIDO",
      esperado == obtido ~ "OK",
      TRUE ~ "DIVERGENTE"
    )
    adicionar_resultado(resumir_status(nome_teste,status))
  }
}
  # Consolida os resumos por teste/status e soma as contagens dos lotes já processados.
  resumo_lote <- bind_rows(resultados_lote)
  resultados[[1L]] <- bind_rows(resultados[[1L]], resumo_lote) %>%
    group_by(teste,status) %>% summarise(n=sum(n),.groups="drop")
  # Atualiza o progresso; o limite impede contabilizar mais linhas que o esperado.
  linhas_testadas <- linhas_testadas + nrow(dataset)
  if (linhas_testadas > total_linhas) stop("A leitura ultrapassou o total esperado de linhas.")
  decorrido <- as.numeric(difftime(Sys.time(), inicio, units="secs"))
  cat(sprintf("[PROGRESSO] %.0f / %.0f linhas | %.1f%% | %.1f minutos\n",
    linhas_testadas, total_linhas, 100*linhas_testadas/total_linhas, decorrido/60))
  rm(dataset, lote, resultados_lote, resumo_lote)
}
rm(reader_testes, scanner_testes, dataset_completo)
if (linhas_testadas != total_linhas) stop("A leitura terminou antes de testar todas as linhas.")

 
# RESUMO FINAL
 
# Junta resumos dos lotes e verificações estruturais. Em cada teste, a soma de n
# deve corresponder ao total de linhas da saída.
resumo_final <- bind_rows(resultados[[1L]], resultados_estrutura) %>% group_by(teste,status) %>% summarise(n=sum(n),.groups="drop") %>% arrange(teste,status)
cat("\n============================================\nRESUMO DOS TESTES\n============================================\n\n")
print(as.data.frame(resumo_final),row.names=FALSE)

# Referências ausentes entram na revisão final, mesmo sem divergência.
# Estes status exigem revisão. SEM REFERÊNCIA é mantido aqui para não ficar
# oculto só porque a descrição vazia coincide com uma tabela incompleta.
problemas <- resumo_final %>% filter(status %in% c(
  "DIVERGENTE", "VALOR NÃO PREENCHIDO", "COLUNA AUSENTE",
  "COLUNA ENRIQUECIDA AUSENTE", "COLUNA PERDIDA NO ENRIQUECIMENTO",
  "COLUNA CRIADA SEM ORIGEM", "SEM REFERÊNCIA", "CÓDIGO NÃO ENCONTRADO",
  "FORMATO DE CID NÃO RECONHECIDO"
))
# Separa ausência na entrada e ausência de detalhamento de subcategoria.
# Esses status não são classificados automaticamente como erro de enriquecimento.
limitacoes <- resumo_final %>% filter(status %in% c(
  "AUSENTE NA BASE ORIGINAL", "SEM CÓDIGO INFORMADO", "SEM CÓDIGO",
  "CÓDIGO NÃO INFORMADO", "CATEGORIA SEM SUBCATEGORIA NA REFERÊNCIA"
))
cat("\n\n")
if(nrow(problemas)==0) cat("Nenhuma divergência ou referência pendente encontrada.\n") else {
  cat("Resultados que precisam de revisão:\n\n")
  print(as.data.frame(problemas),row.names=FALSE)
}
if(nrow(limitacoes)>0) {
  cat("\nInformações ausentes na entrada ou sem detalhamento de subcategoria:\n\n")
  print(as.data.frame(limitacoes),row.names=FALSE)
}

# Salva o resumo completo no CSV definido na configuração, substituindo o anterior.
write.csv(resumo_final,arquivo_resumo,row.names=FALSE,na="")
cat("\nTESTES CONCLUÍDOS. Linhas testadas:",linhas_testadas,"\nResumo salvo em:\n",arquivo_resumo,"\n")
