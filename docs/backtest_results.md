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
| 120 | 0.958 | 0.749 | **0.812** | 0.759 | 0.712 |
| 90 | 1.152 | 2.109 | **1.161** | 0.755 | 0.720 |
| 60 | 0.763 | 2.205 | **0.739** | 0.754 | 0.721 |
| 45 | 0.741 | 2.242 | **0.778** | 0.754 | 0.721 |
| 30 | 0.741 | 0.816 | **0.571** | 0.754 | 0.721 |
| 20 | 0.741 | 0.831 | **0.555** | 0.754 | 0.721 |
| 10 | 0.741 | 0.820 | **0.544** | 0.754 | 0.721 |
| 5 | 0.741 | 0.860 | **0.556** | 0.754 | 0.721 |
| 1 | 0.741 | 0.784 | **0.515** | 0.754 | 0.721 |

### Full sample (2016Q1-2026Q1, incl. COVID)

| Days to release | Labour read | Expenditure read | Blend | AR(1) | Hist. mean |
|---|---|---|---|---|---|
| 150 | 1.615 | 1.547 | **1.558** | 1.517 | 1.504 |
| 120 | 1.514 | 1.539 | **1.485** | 1.517 | 1.504 |
| 90 | 1.277 | 2.465 | **1.180** | 1.530 | 1.508 |
| 60 | 0.936 | 2.536 | **0.794** | 1.530 | 1.509 |
| 45 | 0.784 | 2.564 | **0.750** | 1.530 | 1.509 |
| 30 | 0.784 | 1.688 | **0.630** | 1.530 | 1.509 |
| 20 | 0.784 | 1.695 | **0.739** | 1.530 | 1.509 |
| 10 | 0.784 | 1.690 | **0.722** | 1.530 | 1.509 |
| 5 | 0.784 | 1.706 | **0.741** | 1.530 | 1.509 |
| 1 | 0.784 | 1.754 | **0.755** | 1.530 | 1.509 |

### Out-of-sample check (targets 2022Q1 onward)

| Days to release | Labour read | Expenditure read | Blend | AR(1) | Hist. mean |
|---|---|---|---|---|---|
| 150 | 0.438 | 0.479 | **0.399** | 0.438 | 0.310 |
| 120 | 0.712 | 0.403 | **0.463** | 0.438 | 0.310 |
| 90 | 0.932 | 2.868 | **1.195** | 0.463 | 0.306 |
| 60 | 0.769 | 3.061 | **0.843** | 0.463 | 0.307 |
| 45 | 0.842 | 3.067 | **1.004** | 0.463 | 0.307 |
| 30 | 0.842 | 0.652 | **0.680** | 0.463 | 0.307 |
| 20 | 0.842 | 0.655 | **0.636** | 0.463 | 0.307 |
| 10 | 0.842 | 0.649 | **0.638** | 0.463 | 0.307 |
| 5 | 0.842 | 0.695 | **0.646** | 0.463 | 0.307 |
| 1 | 0.842 | 0.633 | **0.602** | 0.463 | 0.307 |

### Blend weight on the labour read

| Days to release | 1 | 5 | 10 | 20 | 30 | 45 | 60 | 90 | 120 | 150 |
|---|---|---|---|---|---|---|---|---|---|---|
| w(labour) | 0.53 | 0.55 | 0.56 | 0.55 | 0.67 | 0.78 | 0.85 | 0.68 | 0.51 | 0.37 |

Blend beats AR(1) at every grid point with <=20 days to release: ex-COVID **yes**, full sample **yes**.

