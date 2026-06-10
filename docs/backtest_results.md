## Backtest results

Generated 2026-06-10 from vintage `2026-06-10`. Pseudo-real-time, expanding windows, 41 target quarters (2016Q1-2026Q1), evaluated at 10 points in the release cycle. RMSE in percentage points of q/q GDP growth.

### Headline: excluding COVID quarters (2020Q1-2021Q2)

COVID-era GDP swings of several percentage points dominate squared errors and are
not informative about normal-cycle accuracy; the blend weight path is estimated on
this sample. Both reads tracked the COVID collapse directionally, the labour read
far better (see full-sample table).

| Days to release | Labour read | Expenditure read | Blend | AR(1) | Hist. mean |
|---|---|---|---|---|---|
| 150 | 1.000 | 0.771 | **0.833** | 0.759 | 0.712 |
| 120 | 0.958 | 0.749 | **0.787** | 0.759 | 0.712 |
| 90 | 1.152 | 0.948 | **0.898** | 0.755 | 0.720 |
| 60 | 0.763 | 1.529 | **0.745** | 0.754 | 0.721 |
| 45 | 0.741 | 1.522 | **0.709** | 0.754 | 0.721 |
| 30 | 0.741 | 0.709 | **0.552** | 0.754 | 0.721 |
| 20 | 0.741 | 0.831 | **0.556** | 0.754 | 0.721 |
| 10 | 0.741 | 0.820 | **0.544** | 0.754 | 0.721 |
| 5 | 0.741 | 0.860 | **0.556** | 0.754 | 0.721 |
| 1 | 0.741 | 0.784 | **0.515** | 0.754 | 0.721 |

### Full sample (2016Q1-2026Q1, incl. COVID)

| Days to release | Labour read | Expenditure read | Blend | AR(1) | Hist. mean |
|---|---|---|---|---|---|
| 150 | 1.615 | 1.547 | **1.558** | 1.517 | 1.504 |
| 120 | 1.514 | 1.539 | **1.490** | 1.517 | 1.504 |
| 90 | 1.277 | 1.746 | **1.040** | 1.530 | 1.508 |
| 60 | 0.936 | 2.068 | **0.778** | 1.530 | 1.509 |
| 45 | 0.784 | 2.064 | **0.723** | 1.530 | 1.509 |
| 30 | 0.784 | 1.646 | **0.667** | 1.530 | 1.509 |
| 20 | 0.784 | 1.695 | **0.769** | 1.530 | 1.509 |
| 10 | 0.784 | 1.690 | **0.722** | 1.530 | 1.509 |
| 5 | 0.784 | 1.706 | **0.741** | 1.530 | 1.509 |
| 1 | 0.784 | 1.754 | **0.755** | 1.530 | 1.509 |

### Out-of-sample check (targets 2022Q1 onward)

| Days to release | Labour read | Expenditure read | Blend | AR(1) | Hist. mean |
|---|---|---|---|---|---|
| 150 | 0.438 | 0.479 | **0.399** | 0.438 | 0.310 |
| 120 | 0.712 | 0.403 | **0.423** | 0.438 | 0.310 |
| 90 | 0.932 | 0.959 | **0.699** | 0.463 | 0.306 |
| 60 | 0.769 | 2.023 | **0.889** | 0.463 | 0.307 |
| 45 | 0.842 | 2.029 | **0.907** | 0.463 | 0.307 |
| 30 | 0.842 | 0.617 | **0.654** | 0.463 | 0.307 |
| 20 | 0.842 | 0.655 | **0.630** | 0.463 | 0.307 |
| 10 | 0.842 | 0.649 | **0.638** | 0.463 | 0.307 |
| 5 | 0.842 | 0.695 | **0.646** | 0.463 | 0.307 |
| 1 | 0.842 | 0.633 | **0.602** | 0.463 | 0.307 |

### Blend weight on the labour read

| Days to release | 1 | 5 | 10 | 20 | 30 | 45 | 60 | 90 | 120 | 150 |
|---|---|---|---|---|---|---|---|---|---|---|
| w(labour) | 0.53 | 0.55 | 0.56 | 0.53 | 0.61 | 0.70 | 0.67 | 0.53 | 0.39 | 0.37 |

Blend beats AR(1) at every grid point with <=20 days to release: ex-COVID **yes**, full sample **yes**.

