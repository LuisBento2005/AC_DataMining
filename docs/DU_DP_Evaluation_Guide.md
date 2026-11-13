# Guia de Defesa e Mapeamento da Grelha de Avaliação (Data Understanding & Data Preparation)

Este documento liga cada critério de DU e DP da grelha de avaliação aos métodos, figuras e resultados que estão nos notebooks:
- [`notebooks/01_eda.ipynb`](../notebooks/01_eda.ipynb): exploração, eras da NHL, leakage, primeira análise das 3 tasks
- [`notebooks/02_statistical_analysis.ipynb`](../notebooks/02_statistical_analysis.ipynb): análise multivariada e multi-tabela, aprofundamento das 3 tasks
- [`notebooks/03_data_preparation.ipynb`](../notebooks/03_data_preparation.ipynb): integração, qualidade, missing values, outliers, redundância e transformações (tasks a e b)

Todas as figuras estão em [`docs/figures/du/`](figures/du/). **Todos os números deste guia foram copiados dos outputs dos notebooks.** Se um notebook for alterado e re-executado, este guia tem de ser revisto.

---

## 1. Critérios de Data Understanding

| Critério | O que fizemos | Onde está |
|---|---|---|
| **Diversity of statistical methods** | Shapiro-Wilk; Kruskal-Wallis $H$; Levene $W$; Mann-Whitney $U$ + rank-biserial; Pearson e Spearman; $\chi^2$ + Cramér's $V$; correlação point-biserial; VIF; PCA; K-Means vs GMM (Silhouette, Calinski-Harabasz, Davies-Bouldin); OLS com erros robustos HC3 + correlação parcial; sobrevivência estilo Kaplan-Meier por anos de tenure; Logit (odds ratios + IC 95%); índice de dispersão, GLM Poisson vs Negative Binomial (IRRs + IC 95%) | `01` secções 2–6, `02` secções 1–6 |
| **Complexity of statistical methods** | Métodos 3+D: PCA com 12 variáveis de 5 tabelas (4 componentes, 60.0% da variância); clustering 4D no espaço PCA; OLS multivariado HC3 ($n = 660$, $R^2 = 0.393$); Logit multivariado ($n = 681$, LR $p = 0.0005$); NB multivariado para a task (c) ($n = 16{,}521$); estratificação de Simpson (tenure × tercil de pontos → `changed_during`) | `02` secções 2–6 |
| **Interpretation of statistical results** | Cada output tem um bloco *Interpretation & Knowledge Extracted* com estatística de teste, $p$-value, tamanho do efeito ($\rho$, $\beta$, OR, IRR, $V$) e leitura em linguagem de hóquei | Blocos markdown a seguir a cada análise em `01` e `02` |
| **Knowledge extraction (statistics)** | Ver as descobertas principais na secção 3 deste guia | `01` secção 7 e `02` secção 7 (tabelas de síntese) |
| **Diversity of plots** | 18 figuras de DU (`du01`–`du18`) + 4 de DP (`dp01`–`dp04`): Gantt, séries temporais com eixo duplo, violinos, boxplots, regressões, barras agrupadas, scatter 4D, heatmaps, scree plot, biplots com elipses, coordenadas paralelas, curvas de sobrevivência, forest plots, dumbbell, hexbin, histogramas em escala log, frequências observadas vs esperadas | `docs/figures/du/` |
| **Complexity of plots** | `du06`: $x$ = pts% relativo em $t-1$, $y$ = pts% relativo em $t$, tamanho = $\lvert$GD/G$_{t-1}\rvert$, cor/forma = `changed_during`. `du09`: PC1×PC2 e PC1×PC3 com clusters, elipses e vetores de loadings. `du10`: validação de clusters + coordenadas paralelas + taxas por perfil. `du13`: sobrevivência por qualidade da equipa + heatmap de Simpson | `du06`, `du09`, `du10`, `du13` |
| **Presentation** | Títulos com a conclusão (*takeaway titles*), anotações com os testes, paleta consistente, exportação a 300 dpi | Todas as figuras |
| **Interpretation of plots** | Os blocos de interpretação referem os painéis das figuras (ex.: "Panel A of `du13`") | `01` e `02` |
| **Visual knowledge extraction** | Cada secção termina com uma decisão para Data Preparation / Modelling, reunida nas tabelas de síntese | `01` secção 7, `02` secção 7 |

## 2. Critérios de Data Preparation

| Critério | O que fizemos | Onde está |
|---|---|---|
| **Data integration** | Tabelas de treinadores (perfil, histórico, prémios, tenure) + `sql/team_multitable.sql`, que junta `Teams`, `Goalies`, `TeamSplits`, `Scoring`, `Master`, `AwardsPlayers`, `TeamsPost`, `Coaches`, `AwardsCoaches` e `TeamVsTeam` por `franchID` (para seguir as equipas que mudam de `tmID`), com lags `LAG() OVER (PARTITION BY franchID ORDER BY year)` e a ligação 2003 → 2005 por causa do lockout. Para a task (c), `sql/player_pim.sql` soma os stints dos jogadores trocados a meio da época | `03` secções 1 e 4.3.2; [`sql/`](../sql/) |
| **Data quality dimensions** | Uniqueness, consistency, accuracy, validity, completeness e timeliness | `03` secção 2 |
| **Redundancy** | Spearman $\lvert\rho\rvert \ge 0.80$ + VIF; 6 regras de domínio retiram 23 das 53 features (ficam 30). Depois da poda, 28 de 30 têm VIF < 3; o máximo é `pyth_rel_prev` (9.97), daí a regularização L2 nos modelos lineares | `03` secção 7, `dp03` |
| **Missing data** | Taxonomia dos 4 mecanismos (todos estruturais); correções determinísticas (`new_coach = 1` nas equipas de expansão) e flags (`is_rookie_coach`, `is_expansion_team`, `is_second_season`); benchmark walk-forward 2000–2009 de 4 imputers (domain prior, mediana, KNN, MICE) ajustados só em anos < $t$. As diferenças estão na 3.ª–4.ª casa decimal | `03` secção 5, `dp01` |
| **Outliers** | $z$-score univariado ($\lvert z\rvert > 3$) + Isolation Forest ajustado só em anos < 2000. Os casos extremos são reais (DET de Scotty Bowman 1995–2001, OTT 1993–1994, TBL 1998, EDM 1984), por isso não se apaga nenhuma linha; winsorization 1–99% ajustada no treino para os modelos lineares | `03` secção 6, `dp02` |
| **Transformations** | Transformers sem leakage (`LeakFreeDomainImputer`, `TrainingWinsorizer`), `StandardScaler` para modelos lineares, árvores sem escala, discretização para modelos simbólicos; verificação walk-forward Pre-DU vs Post-DU | `03` secção 8, `dp04` |

---

## 3. Descobertas principais (com os números certos)

1. **Leakage do Hall of Fame:** 98.86% (609 de 616) das épocas de jogadores do HOF na NHL em 1982–2009 aconteceram antes da indução. Usar `HOF` sem filtro é usar informação do futuro. (`01` secção 1.1)
2. **Inflação dos pontos com o OTL:** a média da liga de pts% era exatamente 0.500 até 1998 e passou para 0.542 em 1999–2009 (Mann-Whitney $p = 5.9 \times 10^{-8}$). Por isso as features são centradas por época (`_rel`). (`01` secção 2, `du03`)
3. **Mais paridade:** o desvio-padrão de pts% entre equipas caiu de 0.134 (1967–1981) para 0.092 (1999–2009) (Levene $p = 2.3 \times 10^{-9}$), e a correlação de uma época para a seguinte desceu de 0.773 (anos 70) para 0.588 (1982–2009). (`01` secções 2–3)
4. **A sorte não persiste:** controlando a expectativa pitagórica ($\beta = +0.627$, $p < 10^{-80}$), a "sorte" de $t-1$ não tem efeito ($\beta = +0.103$, $p = 0.245$). (`02` secção 4, `du11`)
5. **Shot share e continuidade do plantel** acrescentam informação além da expectativa pitagórica (OLS HC3: $z = 4.04$, $p < 0.0001$; $z = 2.44$, $p = 0.015$). (`02` secção 4, `du11`)
6. **Lua-de-mel do treinador novo (task b):** treinadores contratados no verão são despedidos a meio da época em 10.5% dos casos, contra 20.8% dos que continuam ($\chi^2 = 8.37$, $p = 0.004$). (`01` secção 4, `du05`)
7. **Paradoxo de Simpson (task b):** no total, os treinadores com 4+ anos parecem mais seguros (18.6%) do que os de 2–3 anos (26.5%). No tercil de equipas mais fracas, porém, o risco sobe de 10.5% (ano 0) para 20.0% (ano 1) e 41.8% (anos 2–3). (`02` secção 5, `du13`)
8. **PIM e jogos disputados (task c):** nos totais, PIM e pontos correlacionam a +0.53, mas por jogo a −0.21 (jogadores com 20+ GP). Os jogos disputados explicam 66% da variância de $\log(1+\text{PIM})$. (`02` secção 6, `du17`)
9. **A task (c) é uma contagem sobredispersa:** variância/média = 55. A Poisson falha ($\chi^2/\text{df} = 24$) e a Negative Binomial ajusta muito melhor (AIC 438,699 → 157,378). (`01` secção 6 e `02` secção 6, `du15`, `du17`)

## 4. O que o Data Understanding acrescentou ao Data Preparation

Validação walk-forward 2000–2009 em `03` secção 8 (`dp04`), Pre-DU vs Post-DU:

| Pipeline | Task (a) RMSE | Task (a) $R^2$ | Task (b) ROC-AUC | Task (b) PR-AUC |
|---|---|---|---|---|
| Linear, Pre-DU → Post-DU | 0.0738 → **0.0724** | 0.326 → **0.357** | 0.6181 → **0.6329** | 0.2711 → **0.2759** |
| Random Forest, Pre-DU → Post-DU | 0.0744 → **0.0721** | 0.321 → **0.362** | 0.6521 → 0.6454 | 0.3175 → **0.3522** |

A task (a) melhora nas duas famílias. Na task (b) o PR-AUC melhora nas duas, mas o ROC-AUC do Random Forest desce ligeiramente.

**Limitação a admitir se perguntarem:** as features Post-DU foram escolhidas depois de explorar 1982–2009 inteiro, o que inclui os anos de teste 2000–2009. O ganho é por isso ligeiramente otimista e deve ser confirmado numa época final de hold-out na fase de Modelling.

---

## 5. Perguntas prováveis na defesa

1. ***"Porque é que cortaram o dataset em 1982–2009 (690 linhas)?"***
   - A partir de 1982 a tabela `Goalies` regista os remates sofridos (`SA`) em todas as equipas (`du01`). Sem `SA` não há `save_pct` nem `shot_share`, e o `shot_share` é um dos preditores mais fortes da task (a) (OLS HC3: $z = 4.04$, $p < 0.0001$, `du11`). Os anos anteriores continuam a ser usados para calcular os históricos (lags e carreiras).

2. ***"Porque é que não usaram a tabela `HOF` para medir a qualidade dos jogadores?"***
   - Porque 98.86% das épocas de jogadores do HOF aconteceram antes da indução (`01` secção 1.1). Saber hoje que um jogador vai entrar no HOF é informação do futuro. Medimos o talento com dados de $t-1$: `n_20g_scorers_prev`, `top3_goal_share_prev` e `returning_pts_share_prev`.

3. ***"Qual foi a descoberta mais surpreendente na task (b)?"***
   - O paradoxo de Simpson na antiguidade do treinador (`du13`). No total, os treinadores veteranos parecem mais seguros. Mas, mantendo a qualidade da equipa fixa, o risco de despedimento numa equipa fraca sobe de 10.5% no ano 0 para 41.8% nos anos 2–3. Traduzimos isto na feature `hot_seat_interaction` = min(tenure, 3) × (−`pyth_rel_prev`).

4. ***"Porque é que a task (c) não é uma regressão normal?"***
   - O target é uma contagem com variância 55 vezes maior do que a média, muitos zeros e uma cauda longa de "enforcers". A Poisson não serve ($\chi^2/\text{df} = 24$) e a Negative Binomial ajusta muito melhor (`du17`). Além disso, o total depende dos jogos disputados, que não se sabem antes da época. Por isso propomos prever a taxa por jogo × jogos esperados.

5. ***"Isso é mesmo um Kaplan-Meier?"***
   - É uma estimativa do mesmo tipo (produto das probabilidades de sobreviver a cada ano de tenure), mas calculada a partir de todas as épocas juntas, e não seguindo cada treinador individualmente. Serve para mostrar como o risco evolui com a antiguidade, não para testes formais de sobrevivência.
