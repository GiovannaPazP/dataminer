# Dependências: dplyr manipula tabelas, Arrow lê/grava Parquet e readxl lê a DTB.
# Os pacotes precisam estar instalados antes de executar este script.
library(dplyr)
library(readxl)
library(arrow)

# ENRIQUECIMENTO COMPLETO SIH/SUS - PARQUET - BAIXA MEMORIA
# CONFIGURAÇÃO DOS NOMES: altere os mesmos valores nos dois scripts.
# Estado, ano e meses apenas identificam a saída; todas as linhas são processadas.
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
pasta_anos <- file.path(pasta_sih, "dados_anos")
pasta_parquet <- file.path(pasta_sih, "enriquecimento", "parquet")
pasta_enriquecidos <- file.path(pasta_parquet, "dados enriquecidos")
pasta_aux <- file.path(pasta_sih, "bases_auxiliares")
pasta_dtb <- file.path(pasta_sih, "DTB_2023", "DTB_2023")
pasta_cid <- file.path(pasta_sih, "TABCIH", "TAB_CIH")
# Arquivo bruto efetivamente utilizado. Deve ser o mesmo nos dois scripts.
# Trocar apenas ESTADO/ANO/MESES não muda automaticamente este nome de arquivo.
caminho_entrada <- file.path(pasta_anos, "sih_mg_2016.parquet")
# Dataset em pasta, com arquivos Parquet por lote (baixo consumo de memória).
caminho_saida <- file.path(pasta_enriquecidos, paste0("dados_enriquecidos_", identificador))
# Quantidade de linhas por lote.
# 5000 foi escolhido para reduzir bastante o pico de RAM.
TAMANHO_LOTE <- 5000L

# Colunas excluídas da saída, inclusive enriquecimentos preexistentes.
# Remove campos dispensados e descrições antigas, caso existam na entrada.
# any_of() permite usar a mesma lista mesmo quando algumas colunas não existem.
colunas_excluir <- c("CID_NOTIF", "INFEHOSP", paste0("DIAGSEC", 1:9), paste0("TPDISEC", 1:9),
 "def_infehosp", "def_cid_notif_cap", "def_cid_notif_grupo", "def_cid_notif_cat", "def_cid_notif_subcat",
 as.vector(outer(paste0("def_diagsec", 1:9), c("_cap", "_grupo", "_cat", "_subcat"), paste0)),
 paste0("def_tpdisec", 1:9),
 "UTI_MES_TO", "SEQ_AIH5", "NATUREZA", "REGCT", "FAEC_TP",
 "N_AIH", "GESTAO", "HOMONIMO", "FINANC", "MARCA_UCI", "CNAER",
 "def_diarias_uti", "def_uti_mes_to", "def_seq_aih5", "def_regime", "def_regct",
 "def_faec_tp", "def_n_aih", "def_identific", "def_gestao", "def_homonimo",
 "def_financ", "def_marca_uci", "def_cnae", "def_secun1_princ_cap",
 "def_diag_secun1_grupo", "def_diag_secun1_cat", "def_diag_secun1_subcat")

# FUNÇÕES DOS ENRIQUECIMENTOS EXTERNOS
 
# Converte códigos para texto, remove espaços nas extremidades e trata vazio como NA.
# Não remove zeros à esquerda dos códigos que já foram lidos como texto.
normalizar_codigo <- function(x) {
  x <- trimws(as.character(x)); x[x == ""] <- NA_character_; x
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
  read.csv(file.path(pasta_aux, paste0(nome, ".csv")), sep=";", stringsAsFactors=FALSE,
           colClasses="character", check.names=FALSE) %>%
    transmute(cod=normalizar_codigo(cod), value=trimws(as.character(value))) %>%
    distinct(cod, .keep_all=TRUE)
}
# Os CNV tem cabecalho e campos de largura fixa. O codigo de busca fica
# no ultimo campo, apos um ou mais espacos, seguido de virgula.
# Interpreta arquivos CNV do DATASUS: ignora o cabeçalho e separa descrição/código.
# O código fica no fim da linha. Um ou mais espaços são aceitos antes dele
# para não descartar referências válidas com apenas um espaço separador.
ler_cnv <- function(arquivo, intervalos = FALSE) {
  linhas <- readLines(file.path(pasta_cid, arquivo), encoding="latin1", warn=FALSE)
  linhas <- linhas[-1L]  # cabecalho: quantidade, largura do codigo, tipo
  linhas <- linhas[nzchar(trimws(linhas))]
  extrair <- function(linha) {
    linha <- sub(",\\s*$", "", linha)
    m <- regexec("^\\s*[0-9]+\\s+(.*?)\\s+([A-Z][0-9]{2}(?:[A-Z0-9.]*)?(?:-[A-Z][0-9]{2})?)\\s*$", linha, perl=TRUE)
    p <- regmatches(linha, m)[[1]]
    if (length(p) != 3L) return(c(NA_character_, NA_character_))
    c(p[3], trimws(p[2]))
  }
  if (!length(linhas)) stop("CNV sem linhas de dados: ", arquivo)
  partes <- t(vapply(linhas, extrair, character(2)))
  tabela <- data.frame(cod=partes[,1], value=partes[,2], stringsAsFactors=FALSE)
  if (intervalos) {
    tabela <- tabela[grepl("^[A-Z][0-9]{2}-[A-Z][0-9]{2}$", tabela$cod), , drop=FALSE]
    tabela$inicio <- substr(tabela$cod,1,3)
    tabela$fim <- substr(tabela$cod,5,7)
  } else {
    tabela$cod <- gsub("\\.", "", tabela$cod)
    tabela <- tabela[grepl("^[A-Z][0-9]{2}[A-Z0-9]?$", tabela$cod), , drop=FALSE]
  }
  tabela <- tabela[!is.na(tabela$cod) & nzchar(tabela$value), , drop=FALSE]
  tabela <- tabela[!duplicated(tabela$cod), , drop=FALSE]
  if (!nrow(tabela)) stop("Nenhuma referência CID lida em: ", arquivo)
  tabela
}

# Retorna a descricao do intervalo que contem cada categoria (vetorizado).
# Obtém capítulo ou grupo pela categoria de três caracteres. Ex.: O80 pertence
# ao intervalo O00-O99. Em intervalos sobrepostos, mantém o primeiro da tabela.
mapear_intervalos <- function(codigos, tabela) {
  x <- substr(normalizar_codigo(codigos), 1, 3)
  res <- rep(NA_character_, length(x))
  for (i in seq_len(nrow(tabela))) {
    ok <- !is.na(x) & x >= tabela$inicio[i] & x <= tabela$fim[i] & is.na(res)
    res[ok] <- tabela$value[i]
  }
  res
}

# Acrescenta as quatro descricoes a um campo CID, sem remover o codigo.
# Acrescenta capítulo, grupo, categoria e subcategoria ao campo informado.
# A categoria usa os três primeiros caracteres; a subcategoria usa o código completo.
# Sem correspondência, mantém NA; não inventa uma subcategoria para um código de categoria.
enriquecer_cid <- function(dados, coluna, prefixo) {
  if (!coluna %in% names(dados)) return(dados)
  codigo <- normalizar_cid(dados[[coluna]])
  categoria <- substr(codigo, 1, 3)
  dados[[paste0(prefixo, "_cap")]] <- mapear_intervalos(categoria, cid_capitulos)
  dados[[paste0(prefixo, "_grupo")]] <- mapear_intervalos(categoria, cid_grupos)
  dados[[paste0(prefixo, "_cat")]] <- unname(setNames(cid_categorias$value, cid_categorias$cod)[categoria])
  dados[[paste0(prefixo, "_subcat")]] <- unname(setNames(cid_subcategorias$value, cid_subcategorias$cod)[codigo])
  dados
}

 

# MUNICÍPIO, ESTADO E PAÍS - DTB 2023
 
# MUNIC_MOV = município do estabelecimento / movimentação
# MUNIC_RES = município de residência
# O código SIH usa os 6 primeiros dígitos do código IBGE completo.

mapa_uf <- c(
  "11"="Rondônia", "12"="Acre", "13"="Amazonas", "14"="Roraima",
  "15"="Pará", "16"="Amapá", "17"="Tocantins", "21"="Maranhão",
  "22"="Piauí", "23"="Ceará", "24"="Rio Grande do Norte", "25"="Paraíba",
  "26"="Pernambuco", "27"="Alagoas", "28"="Sergipe", "29"="Bahia",
  "31"="Minas Gerais", "32"="Espírito Santo", "33"="Rio de Janeiro",
  "35"="São Paulo", "41"="Paraná", "42"="Santa Catarina",
  "43"="Rio Grande do Sul", "50"="Mato Grosso do Sul", "51"="Mato Grosso",
  "52"="Goiás", "53"="Distrito Federal"
)

# A DTB fornece nome e código dos municípios. O SIH usa os seis primeiros
# dígitos do código IBGE completo. Cada código fica com uma única referência.
municipios <- readxl::read_excel(
  file.path(pasta_dtb,"RELATORIO_DTB_BRASIL_MUNICIPIO.xls"),
  skip=6, col_types="text"
) %>%
  transmute(
    codigo_ibge=normalizar_codigo(`Código Município Completo`),
    cidade=trimws(as.character(`Nome_Município`))
  ) %>%
  filter(!is.na(codigo_ibge), !is.na(cidade)) %>%
  mutate(
    codigo_sih=substr(codigo_ibge,1,6),
    estado=unname(mapa_uf[substr(codigo_ibge,1,2)]),
    pais="Brasil"
  ) %>%
  distinct(codigo_sih,.keep_all=TRUE)



 
# TABELAS DE REFERENCIA - CARREGADAS UMA VEZ
 
cat("[PREPARACAO] Carregando tabelas auxiliares...\n")

ETNIA_aux <- ler_auxiliar("ETNIA")
NACION3D <- ler_auxiliar("NACION3D")
CBO_aux <- ler_auxiliar("CBO")
LEITOS_aux <- ler_auxiliar("LEITOS")
SIGTAP <- ler_auxiliar("TB_SIGTAB")

cat("[PREPARACAO] Carregando tabelas CID-10...\n")

cid_capitulos <- ler_cnv("CID10CAP.CNV", intervalos=TRUE)
cid_grupos <- ler_cnv("CID10GRUPO.CNV", intervalos=TRUE)
cid_categorias <- ler_cnv("CID10_3D.CNV")
cid_subcategorias <- bind_rows(
  lapply(sprintf("CID10_%02d.CNV", 1:22), ler_cnv)
) %>%
  distinct(cod, .keep_all = TRUE)

cat("[PREPARACAO] Tabelas de referencia prontas.\n")


 
# FUNCAO: ENRIQUECER UM LOTE
 
# Aplica todas as transformações a um único lote e devolve suas linhas enriquecidas.
# As referências já carregadas são reutilizadas em todos os lotes.
enriquecer_lote <- function(dados) {
  dados <- dados %>% select(-any_of(colunas_excluir))

# DECODIFICAÇÕES SIH/SUS
 


 
# FUNÇÃO AUXILIAR
 

# Traduz um vetor usando um mapa código -> descrição. Se a coluna não existir,
# devolve um NA por linha do lote. Código presente sem mapeamento resulta em texto vazio.
decodificar <- function(coluna, mapa) {

  # Em algumas bases do SIH/SUS certas colunas nao existem.
  # Nesse caso, mantemos o numero de linhas do lote e indicamos
  # que nao foi possivel calcular a decodificacao.
  if (is.null(coluna) || length(coluna) == 0L) {
    return(rep(NA_character_, nrow(dados)))
  }

  resultado <- unname(
    mapa[as.character(coluna)]
  )

  # Mantem a regra original para codigos presentes mas nao mapeados.
  resultado[is.na(resultado)] <- ""

  return(resultado)
}


 
# 3. IDENT
 

# Os mapas abaixo mantêm a coluna original e geram uma nova coluna def_*.
# Cada chave à esquerda é um código; o texto à direita é a descrição correspondente.
mapa_ident <- c(
  "1" = "Normal",
  "5" = "Longa permanência",
  "0" = "",
  "9" = ""
)

dados$def_ident <- decodificar(
  dados$IDENT,
  mapa_ident
)


 
# 4. VINCPREV
 

mapa_vincprev <- c(
  "1" = "Autônomo",
  "2" = "Desempregado",
  "3" = "Aposentado",
  "4" = "Não segurado",
  "5" = "Empregado",
  "6" = "Empregador"
)

dados$def_vincprev <- decodificar(
  dados$VINCPREV,
  mapa_vincprev
)


 
# 6. NUM_FILHOS
 

mapa_num_filhos <- c(
  "0"  = "Sem filhos/Não inform",
  "1"  = "1 filho",
  "2"  = "2 filhos",
  "3"  = "3 filhos",
  "4"  = "4 a 5 filhos",
  "5"  = "4 a 5 filhos",
  "6"  = "6 a 9 filhos",
  "7"  = "6 a 9 filhos",
  "8"  = "6 a 9 filhos",
  "9"  = "6 a 9 filhos",
  "10" = "10 filhos ou mais",
  "99" = "10 filhos ou mais"
)

dados$def_num_filhos <- decodificar(
  dados$NUM_FILHOS,
  mapa_num_filhos
)


 
# 9. DIAS_PERM
 

mapa_dias_perm <- c(
  "0000" = "0 dias",
  "0001" = "1 dia",
  "0002" = "2 dias",
  "0003" = "3 dias",
  "0004" = "4 dias",
  "0005" = "5 dias",
  "0006" = "6 dias",
  "0007" = "7 dias",
  "0014" = "8-14 dias",
  "0021" = "15-21 dias",
  "0028" = "22-28 dias",
  "9999" = "29 dias e +"
)

dados$def_dias_perm <- decodificar(
  dados$DIAS_PERM,
  mapa_dias_perm
)


 
# 11. CAR_INT
 

mapa_car_int <- c(
  "1" = "Eletivo",
  "2" = "Urgência",
  "3" = "Acidente no local trabalho ou a serv da empresa",
  "4" = "Acidente no trajeto para o trabalho",
  "5" = "Outros tipo de acidente de trânsito",
  "6" = "Out tp lesões e envenen por agent quím físicos"
)

dados$def_car_int <- decodificar(
  dados$CAR_INT,
  mapa_car_int
)


 
# 13. SEXO
 

mapa_sexo <- c(
  "1" = "Masculino",
  "2" = "Feminino",
  "3" = "Feminino",
  "0" = "",
  "9" = ""
)

dados$def_sexo <- decodificar(
  dados$SEXO,
  mapa_sexo
)


 
# 14. MARCA_UTI
 

mapa_marca_uti <- c(
  "00" = "Não utilizou UTI",
  "74" = "UTI adulto - tipo I",
  "75" = "UTI adulto - tipo II",
  "76" = "UTI adulto - tipo III",
  "77" = "UTI infantil - tipo I",
  "78" = "UTI infantil - tipo II",
  "79" = "UTI infantil - tipo III",
  "80" = "UTI neonatal - tipo I",
  "81" = "UTI neonatal - tipo II",
  "82" = "UTI neonatal - tipo III",
  "83" = "UTI de queimados",
  "85" = "UTI coronariana tipo II - UCO tipo II",
  "86" = "UTI coronariana tipo III - UCO tipo III",
  "99" = "UTI Doador",
  "01" = "Utilizou mais de um tipo de UTI"
)

dados$def_marca_uti <- decodificar(
  dados$MARCA_UTI,
  mapa_marca_uti
)


 
# 16. IND_VDRL
 

mapa_ind_vdrl <- c(
  "0" = "Não",
  "1" = "Sim"
)

dados$def_ind_vdrl <- decodificar(
  dados$IND_VDRL,
  mapa_ind_vdrl
)


 
# 17. COD_IDADE
 

mapa_cod_idade <- c(
  "2" = "Dias",
  "3" = "Meses",
  "4" = "Anos",
  "0" = ""
)

dados$def_cod_idade <- decodificar(
  dados$COD_IDADE,
  mapa_cod_idade
)


 
# 18. MORTE
 

mapa_morte <- c(
  "0" = "Sem óbito",
  "1" = "Com óbito"
)

dados$def_morte <- decodificar(
  dados$MORTE,
  mapa_morte
)


 
# 20. INSTRU
 

mapa_instru <- c(
  "1" = "Analfabeto",
  "2" = "1º grau",
  "3" = "2º grau",
  "4" = "3º grau",
  "0" = "",
  "9" = ""
)

dados$def_instru <- decodificar(
  dados$INSTRU,
  mapa_instru
)


 
# 21. CONTRACEP1
 

mapa_contracep <- c(
  "01" = "LAM",
  "02" = "Ogino Kaus",
  "03" = "Temperatura basal",
  "04" = "Billings",
  "05" = "Cinto térmico",
  "06" = "DIU",
  "07" = "Diafragma",
  "08" = "Preservativo",
  "09" = "Espermicida",
  "10" = "Hormônio oral",
  "11" = "Hormônio injetável",
  "12" = "Coito interrompido",
  "00" = "",
  "99" = ""
)

dados$def_contracep1 <- decodificar(
  dados$CONTRACEP1,
  mapa_contracep
)


 
# 22. CONTRACEP2
 

dados$def_contracep2 <- decodificar(
  dados$CONTRACEP2,
  mapa_contracep
)


 
# 23. GESTRISCO
 

mapa_sim_nao <- c(
  "0" = "Não",
  "1" = "Sim"
)

dados$def_gestrisco <- decodificar(
  dados$GESTRISCO,
  mapa_sim_nao
)


 
# 25. COMPLEX
 

mapa_complex <- c(
  "01" = "Atenção Básica",
  "02" = "Média complexidade",
  "03" = "Alta complexidade",
  "00" = "",
  "99" = ""
)

dados$def_complex <- decodificar(
  dados$COMPLEX,
  mapa_complex
)


 
# 27. RACA_COR
 

mapa_raca_cor <- c(
  "01" = "Branca",
  "02" = "Preta",
  "03" = "Parda",
  "04" = "Amarela",
  "05" = "Indígena",
  "99" = "Sem Informação"
)

dados$def_raca_cor <- decodificar(
  dados$RACA_COR,
  mapa_raca_cor
)


 

# Associa município do estabelecimento e município de residência à DTB.
# left_join mantém as linhas da base; códigos não encontrados ficam sem descrição.
dados <- dados %>%
  mutate(
    MUNIC_MOV=normalizar_codigo(MUNIC_MOV),
    MUNIC_RES=normalizar_codigo(MUNIC_RES)
  ) %>%
  left_join(
    municipios %>% transmute(
      MUNIC_MOV=codigo_sih, cidade_int=cidade, estado_int=estado, pais_int=pais
    ),
    by="MUNIC_MOV"
  ) %>%
  left_join(
    municipios %>% transmute(
      MUNIC_RES=codigo_sih, cidade_res=cidade, estado_res=estado, pais_res=pais
    ),
    by="MUNIC_RES"
  )

 

# TABELAS AUXILIARES
 
# Os joins seguintes consultam etnia, nacionalidade, ocupação, leito e procedimento.
# A descrição de etnia NÃO INFORMADO é convertida em NA.
# ETNIA
dados <- dados %>% mutate(ETNIA=normalizar_codigo(ETNIA)) %>%
  left_join(ETNIA_aux %>% rename(ETNIA=cod,def_etnia=value),by="ETNIA") %>%
  mutate(def_etnia=na_if(def_etnia,"NÃO INFORMADO"))
# Nacionalidade
dados <- dados %>% mutate(NACIONAL=normalizar_codigo(NACIONAL)) %>%
  left_join(NACION3D %>% rename(NACIONAL=cod,def_nacionalidade=value),by="NACIONAL")
# CBO (entrada CBOR)
dados <- dados %>% mutate(CBOR=normalizar_codigo(CBOR)) %>%
  left_join(CBO_aux %>% rename(CBOR=cod,def_cbo=value),by="CBOR")
# Leitos
dados <- dados %>% mutate(ESPEC=normalizar_codigo(ESPEC)) %>%
  left_join(LEITOS_aux %>% rename(ESPEC=cod,def_leitos=value),by="ESPEC")
# Procedimentos
dados <- dados %>% mutate(PROC_REA=normalizar_codigo(PROC_REA),PROC_SOLIC=normalizar_codigo(PROC_SOLIC)) %>%
  left_join(SIGTAP %>% rename(PROC_REA=cod,def_procedimento_realizado=value),by="PROC_REA") %>%
  left_join(SIGTAP %>% rename(PROC_SOLIC=cod,def_procedimento_solicitado=value),by="PROC_SOLIC")

 

# CID-10: preserva os codigos e enriquece todos os diagnosticos presentes.
# A funcao usa vetores e nao multiplica linhas em joins.
campos_cid <- c("DIAG_PRINC", "DIAG_SECUN", "CID_ASSO", "CID_MORTE")
for (campo in intersect(campos_cid, names(dados))) {
  prefixo <- if (campo == "DIAG_PRINC") "def_diag_princ" else
    if (campo == "DIAG_SECUN") "def_diag_secun" else
    paste0("def_", tolower(campo))
  dados <- enriquecer_cid(dados, campo, prefixo)
}
 

# As datas originais são interpretadas como AAAAMMDD e geram ano e dia da semana.
# O nome do dia depende do idioma da sessão R.
# Na regra atual, COD_IDADE menor que 4 é agrupado em zero anos para as faixas.
# As faixas etárias são agrupamentos analíticos; não são uma conversão exata de dias/meses.
# DATAS E IDADE
 
dados <- dados %>% mutate(
  dt_inter=as.Date(as.character(DT_INTER),format="%Y%m%d"), dt_saida=as.Date(as.character(DT_SAIDA),format="%Y%m%d"),
  ano_internacao=as.integer(format(dt_inter,"%Y")), dia_semana_internacao=weekdays(dt_inter),
  ano_saida=as.integer(format(dt_saida,"%Y")), dia_semana_saida=weekdays(dt_saida),
  IDADE_num=suppressWarnings(as.numeric(IDADE)), COD_IDADE_num=suppressWarnings(as.numeric(COD_IDADE)),
  def_idade_anos=case_when(is.na(IDADE_num)|is.na(COD_IDADE_num)~NA_real_,COD_IDADE_num<4~0,TRUE~IDADE_num),
  def_idade_bas=case_when(is.na(def_idade_anos)~NA_character_,def_idade_anos<1~"<1a",def_idade_anos<5~"1-4a",def_idade_anos<15~"5-14a",def_idade_anos<50~"15-49a",TRUE~"50e+a"),
  def_idade_pub=case_when(is.na(def_idade_anos)~NA_character_,def_idade_anos<1~"<1a",def_idade_anos<5~"1-4a",def_idade_anos<15~"5-14a",def_idade_anos<25~"15-24a",def_idade_anos<35~"25-34a",def_idade_anos<45~"35-44a",def_idade_anos<55~"45-54a",def_idade_anos<65~"55-64a",TRUE~"65e+a"),
  def_idade_18=case_when(is.na(def_idade_anos)~NA_character_,def_idade_anos<1~"<1a",def_idade_anos<5~"1-4a",def_idade_anos<10~"5-9a",def_idade_anos<15~"10-14a",def_idade_anos<20~"15-19a",def_idade_anos<25~"20-24a",def_idade_anos<30~"25-29a",def_idade_anos<35~"30-34a",def_idade_anos<40~"35-39a",def_idade_anos<45~"40-44a",def_idade_anos<50~"45-49a",def_idade_anos<55~"50-54a",def_idade_anos<60~"55-59a",def_idade_anos<65~"60-64a",def_idade_anos<70~"65-69a",def_idade_anos<75~"70-74a",def_idade_anos<80~"75-79a",TRUE~"80e+a")
) %>% select(-IDADE_num,-COD_IDADE_num)

 


  dados
}


 
# LEITURA E PROCESSAMENTO EM LOTES
# Arrow 25.0.1: Dataset -> Scanner -> RecordBatchReader
 
cat("[INICIO] Abrindo arquivo de entrada:", caminho_entrada, "\n")

dataset_entrada <- arrow::open_dataset(
  caminho_entrada,
  format = "parquet"
)

# O Scanner limita cada lote a TAMANHO_LOTE linhas. O leitor avança até retornar NULL.
# Isso evita carregar toda a base enriquecida de uma vez na memória.
scanner <- arrow::Scanner$create(
  dataset_entrada,
  batch_size = TAMANHO_LOTE
)

reader <- scanner$ToRecordBatchReader()

cat("[INICIO] RecordBatchReader criado.\n")
cat("[INICIO] Tamanho maximo por lote:", TAMANHO_LOTE, "linhas\n")

# A saída continua em Parquet, como um dataset (pasta com part-*.parquet).
# Não juntamos os lotes novamente na memória.
# Reexecutar substitui a pasta de saída deste identificador: os lotes anteriores
# são removidos antes da gravação. O arquivo bruto não é apagado.
if (dir.exists(caminho_saida)) {
  unlink(caminho_saida, recursive = TRUE, force = TRUE)
} else if (file.exists(caminho_saida)) {
  file.remove(caminho_saida)
}
dir.create(caminho_saida, recursive = TRUE, showWarnings = FALSE)

total_linhas <- 0L
total_colunas <- NA_integer_
i <- 0L

repeat {
  # read_next_batch() devolve NULL quando todos os lotes terminarem.
  batch <- reader$read_next_batch()

  if (is.null(batch)) {
    break
  }

  i <- i + 1L

  cat(sprintf("\n[LOTE %d] Convertendo batch para data.frame...\n", i))

  dados <- as.data.frame(batch)

  # Informa uma unica vez quais colunas de decodificacao estao ausentes.
  # A funcao decodificar() criara as colunas def_* com NA nesses casos.
  if (i == 1L) {
    colunas_decodificar <- c(
      "IDENT", "VINCPREV", "NUM_FILHOS", "DIAS_PERM", "CAR_INT",
      "SEXO", "MARCA_UTI", "IND_VDRL", "COD_IDADE", "MORTE",
      "INSTRU", "CONTRACEP1", "CONTRACEP2", "GESTRISCO",
      "COMPLEX", "RACA_COR"
    )
    colunas_ausentes <- setdiff(colunas_decodificar, names(dados))
    if (length(colunas_ausentes) > 0L) {
      cat("[AVISO] Colunas de decodificacao ausentes: ",
          paste(colunas_ausentes, collapse = ", "), "\n", sep = "")
      cat("[AVISO] Os respectivos enriquecimentos serao preenchidos com NA.\n")
    }
  }

  # Todas as linhas do arquivo de entrada são enriquecidas.
  linhas_entrada <- nrow(dados)

  cat(sprintf(
    "[LOTE %d] %d linhas recebidas. Enriquecendo...\n",
    i, linhas_entrada
  ))

  # Enriquece somente o lote atual; a próxima verificação impede joins de ampliar linhas.
  dados <- enriquecer_lote(dados)

  # Segurança: nenhum left_join deve multiplicar registros.
  if (nrow(dados) != linhas_entrada) {
    stop(
      sprintf(
        paste0(
          "O lote %d entrou com %d linhas e saiu com %d. ",
          "Um join multiplicou registros."
        ),
        i, linhas_entrada, nrow(dados)
      )
    )
  }

  total_colunas <- ncol(dados)

  arquivo_lote <- file.path(
    caminho_saida,
    sprintf("dados_enriquecidos_%s_part-%05d.parquet", identificador, i)
  )

  cat(sprintf("[LOTE %d] Gravando %s...\n", i, basename(arquivo_lote)))

  # Cada lote é gravado como arquivo Parquet na mesma pasta de dataset.
  # Snappy comprime os dados. Abra a pasta com open_dataset() para ler o conjunto.
  arrow::write_parquet(
    dados,
    arquivo_lote,
    compression = "snappy"
  )

  total_linhas <- total_linhas + linhas_entrada

  # Remove somente objetos do lote atual.
  # Libera as referências aos objetos grandes do lote, sem acumular lotes na memória.
  rm(dados, batch)

  cat(sprintf(
    "[LOTE %d] OK | Total processado: %d linhas | Colunas finais: %d\n",
    i, total_linhas, total_colunas
  ))
}

rm(reader, scanner, dataset_entrada)
if (total_linhas == 0L) stop("O arquivo dados_SIH.parquet não contém registros.")

cat("\n\n")
cat("ENRIQUECIMENTO CONCLUIDO\n")
cat("\n")
cat("Entrada preservada:\n", caminho_entrada, "\n")
cat("Dataset Parquet enriquecido:\n", caminho_saida, "\n")
cat("Arquivos gravados:", length(list.files(caminho_saida, pattern="[.]parquet$")), "\n")
cat("Linhas processadas:", total_linhas, "\n")
cat("Colunas finais:", total_colunas, "\n")

cat("\nPara abrir o resultado:\n")
cat("dataset <- arrow::open_dataset(caminho_saida, format = 'parquet')\n")
