---
title: Agent 評估工具與框架全攻略
description: 深入比較 LangSmith、Google ADK、Claude SDK 及開源工具的評估能力，幫你選擇適合的技術棧
date: 2026-02-02
slug: ai-engineering-001-agent-evaluation-tools
series: "ai-engineering"
tags:
  - "ai-engineering"
  - "agent"
  - "evaluation"
  - "note"
---

:::note
**前置閱讀**

本文假設你已經讀過系列的前一篇文章：
- [為什麼需要評估 AI Agent？](/posts/ai-engineering-000-agent-evaluation-why)——理解評估的四個維度與 Trajectory/Output 的區別

本文會使用「LLM-as-Judge」、「Trajectory」、「Golden Dataset」等術語。
:::

上一篇我們談了「為什麼」需要評估 Agent，這篇來看「用什麼工具」。

## 框架版圖一覽

在開始之前，先解釋幾個會反覆出現的概念：

:::info
**關鍵術語**

- **Observability（可觀測性）**：追蹤系統內部狀態的能力。對 Agent 來說，就是記錄它的每一步執行、每次 LLM 呼叫、每個工具使用。和傳統「監控」不同，observability 更強調「能回答任意問題」，而非只看預設指標。

- **Tracing（追蹤）**：記錄 Agent 執行的完整過程，包含每個步驟的輸入輸出。類似程式的 debug log，但更結構化。

- **Golden Dataset（黃金資料集）**：一組「完美」的互動範例，作為評估的參考標準。類似考試的標準答案。
:::

目前 Agent 評估工具可以分成三類：

```
┌─────────────────────────────────────────────────────────┐
│               Agent 評估工具生態系                        │
├─────────────────────────────────────────────────────────┤
│  框架內建評估（開發 Agent 的框架自帶評估功能）              │
│  ├─ LangSmith (LangChain 生態)                          │
│  ├─ Google ADK (Vertex AI 生態)                         │
│  └─ Claude SDK + 第三方整合                              │
├─────────────────────────────────────────────────────────┤
│  獨立評估框架（專門做評估，與 Agent 框架無關）             │
│  ├─ DeepEval (開源，類 pytest)                          │
│  ├─ Inspect AI (UK AISI，安全導向)                      │
│  └─ OpenAI Evals                                        │
├─────────────────────────────────────────────────────────┤
│  Observability 平台（追蹤 + 監控 + 分析）                │
│  ├─ Langfuse (開源)                                     │
│  ├─ Arize Phoenix (開源)                                │
│  └─ AgentOps (商業)                                     │
└─────────────────────────────────────────────────────────┘
```

讓我們逐一深入。

---

## LangSmith：最成熟的商業方案

[LangSmith](https://www.langchain.com/langsmith) 是 LangChain 公司的商業產品，提供完整的 observability + evaluation 整合。

:::tip
**什麼是 LangChain？**

LangChain 是目前最流行的 LLM 應用開發框架（Python/JS），提供統一的介面來串接不同的 LLM、工具、資料庫。LangSmith 則是它的配套商業服務，專門處理追蹤與評估。
:::

### 核心功能

**1. Tracing（追蹤）**

每個 Agent 執行都會被記錄成一棵 trace tree：

```
Trace: "幫我查詢訂單狀態"
├─ LLM Call: 理解意圖
│   ├─ Input: "幫我查詢訂單狀態"
│   └─ Output: "需要呼叫 get_order_status"
├─ Tool Call: get_order_status
│   ├─ Input: {"order_id": "12345"}
│   └─ Output: {"status": "shipped", "eta": "2024-01-17"}
└─ LLM Call: 組織回應
    ├─ Input: 訂單資料
    └─ Output: "您的訂單已出貨，預計 1/17 送達"
```

重點：**零延遲影響**。LangSmith SDK 使用非同步機制，不會拖慢你的 Agent。

**2. Multi-turn Evals（2025 新功能）**

傳統評估看單一回合，但真實 Agent 對話常常是多輪的。LangSmith 現在支援：

| 評估類型 | 說明 |
|----------|------|
| Semantic Intent | 用戶真正想做什麼 |
| Semantic Outcome | 任務是否完成 |
| Agent Trajectory | 互動過程如何展開 |

```python
# 定義 multi-turn eval
eval_config = {
    "type": "multi_turn",
    "judge_prompt": """
    分析這個對話：
    1. 用戶的意圖是什麼？
    2. Agent 是否成功達成？
    3. 過程中有哪些問題？
    """
}
```

**3. Insights Agent**

這是 LangSmith 的殺手級功能——用 AI 分析你的 traces，自動發現：
- 常見失敗模式
- 異常行為模式
- 效能瓶頸

**4. Polly（2025/12 推出）**

聊天式 trace 分析工具。你可以直接問：
- 「這個 Agent 有沒有做多餘的事？」
- 「為什麼這個 case 失敗了？」
- 「最近一週最常見的錯誤是什麼？」

### 評估方法

LangSmith 支援三種評估方法：

| 方法 | 用途 | 範例 |
|------|------|------|
| **Heuristic（啟發式）** | 寫死的規則檢查 | 回應是否為空？程式碼能否編譯？ |
| **LLM-as-Judge** | 用另一個 LLM 評分 | 回應是否專業？資訊是否正確？ |
| **Pairwise（成對比較）** | 比較兩個輸出 | A 和 B 哪個回應更好？ |

### 適合誰？

- 已經使用 LangChain / LangGraph 的團隊
- 需要「開箱即用」完整解決方案
- 願意付費換取省時間

---

## Google ADK：開源 + Vertex AI 整合

[Google ADK](https://google.github.io/adk-docs/) 是 Google 開源的 Agent 開發框架，評估功能分成兩層：

### Inner Loop：開發階段

```bash
# 互動式測試
adk web

# 程式化評估
adk eval --evalset golden_dataset.json
```

**Trajectory Matching** 是 ADK 的特色功能：

```python
eval_config = {
    "trajectory_match_mode": "IN_ORDER",  # 或 EXACT, ANY_ORDER
    "expected_tools": ["search_product", "check_inventory", "create_order"]
}
```

三種模式的差異：

| 模式 | 說明 | 寬鬆度 |
|------|------|--------|
| `EXACT` | 完全匹配，不能有額外步驟 | 最嚴格 |
| `IN_ORDER` | 順序正確，允許額外步驟 | 中等 |
| `ANY_ORDER` | 包含所有必要工具即可 | 最寬鬆 |

### Outer Loop：生產階段

整合 Vertex AI 進行大規模評估：

```python
from vertexai.evaluation import EvalTask

eval_task = EvalTask(
    dataset="gs://my-bucket/eval-dataset.jsonl",
    metrics=[
        "final_response_match_v2",  # 語意匹配
        "hallucinations_v1",         # 幻覺偵測
        "safety_v1"                  # 安全性
    ]
)

results = eval_task.evaluate(model="gemini-2.0-flash")
```

### Golden Dataset 概念

ADK 鼓勵你收集「完美」的互動作為參考：

```json
{
  "input": "幫我訂明天下午的會議室",
  "expected_output": "已為您預訂...",
  "expected_trajectory": [
    {"tool": "check_availability", "args": {"date": "2024-01-16"}},
    {"tool": "book_room", "args": {"room": "A301"}}
  ]
}
```

這些 Golden Dataset 可以：
1. 作為 regression test
2. 評估新版 Agent 是否退步
3. 訓練更好的 Judge LLM

### 適合誰？

- Google Cloud / Vertex AI 用戶
- 想要開源方案但不排斥雲端服務
- 重視 Trajectory 評估

---

## Claude Agent SDK：整合導向

[Claude Agent SDK](https://platform.claude.com/docs/en/agent-sdk/overview) 採取不同策略——SDK 本身不內建評估，而是強調與第三方工具整合。

### 官方建議

Anthropic 的建議是：

> 「改進 Agent 最好的方法是仔細觀察它的輸出，特別是失敗的案例，並試著站在 Agent 的角度思考。」

這聽起來很「手工」，但背後的哲學是：**沒有一體適用的評估方案**。

### Observability 整合

Claude SDK 與多個平台有原生整合：

| 平台 | 整合方式 | 特點 |
|------|----------|------|
| [MLflow](https://mlflow.org/blog/mlflow-autolog-claude-agents-sdk) | `@mlflow.anthropic.autolog()` | 自動追蹤，零代碼 |
| [Langfuse](https://langfuse.com/integrations/frameworks/claude-agent-sdk) | SDK callback | 開源，可自架 |
| [LangSmith](https://docs.langchain.com/langsmith/trace-claude-agent-sdk) | 原生支援 | 完整功能 |
| [Arize Phoenix](https://arize.com/blog/claude-code-observability-and-tracing-introducing-dev-agent-lens/) | Dev-Agent-Lens | OpenTelemetry 標準 |

### MLflow 整合範例

```python
import mlflow
from anthropic import Anthropic

# 一行開啟自動追蹤
mlflow.anthropic.autolog()

client = Anthropic()
response = client.messages.create(
    model="claude-sonnet-4-20250514",
    messages=[{"role": "user", "content": "..."}]
)

# 自動記錄：inputs, outputs, latency, tokens
```

### 適合誰？

- 使用 Claude 模型的團隊
- 想要彈性選擇 observability 平台
- 不想被單一框架鎖定

---

## 獨立評估框架

如果你的 Agent 不是用上述框架建構，或者你想要更多控制權，這些獨立工具值得考慮：

### DeepEval

[DeepEval](https://github.com/confident-ai/deepeval) 是開源的 LLM 評估框架，設計理念類似 pytest：

```python
from deepeval import evaluate
from deepeval.metrics import ToolCorrectnessMetric
from deepeval.test_case import LLMTestCase

# 定義測試案例
test_case = LLMTestCase(
    input="幫我查詢訂單狀態",
    actual_output=agent_response,
    expected_tools=["get_order_status"],
    actual_tools=["get_order_status", "get_user_info"]  # 多呼叫了一個
)

# 評估
metric = ToolCorrectnessMetric()
evaluate([test_case], [metric])
```

**Agent 專用 Metrics**：
- `ToolCorrectnessMetric`：工具選擇正確性
- `ArgumentCorrectnessMetric`：參數正確性
- `TaskCompletionMetric`：任務完成度

**優點**：
- 開源免費
- 類 pytest 語法，學習曲線低
- 50+ 內建 metrics
- 支援 CI/CD 整合

### Inspect AI

[Inspect AI](https://inspect.aisi.org.uk/) 是 UK AI Security Institute 開發的評估框架，特別強調安全性：

```python
from inspect_ai import Task, task
from inspect_ai.scorer import model_graded_qa
from inspect_ai.solver import generate

@task
def my_eval():
    return Task(
        dataset="my_dataset.jsonl",
        solver=generate(),
        scorer=model_graded_qa()
    )
```

**特點**：
- 100+ 預建 evaluations（包含 SWE-bench、GAIA）
- Docker sandbox 隔離執行（在獨立容器中運行 Agent，避免影響主系統）
- 被 Anthropic、DeepMind、Grok 等公司採用
- 專為安全評估設計

:::info
**什麼是 Docker Sandbox？**

當 Agent 需要執行程式碼或操作檔案系統時，直接在主機上執行可能有風險。Docker sandbox 提供一個隔離的「沙盒」環境，Agent 的操作不會影響到真實系統。這對安全評估特別重要。
:::

**適合場景**：
- 需要評估 Agent 的安全性
- 需要隔離執行環境
- 學術研究

### OpenAI Evals

[OpenAI Evals](https://github.com/openai/evals) 是 OpenAI 的開源評估框架：

```yaml
# eval.yaml
my_eval:
  id: my_eval
  metrics: [accuracy]

eval_set:
  - input: "..."
    expected: "..."
```

**特點**：
- YAML 配置，不需寫程式
- 支援 LLM-graded 評估
- 有公開的 benchmark registry

---

## Observability 平台對比

評估需要資料，observability 平台負責收集這些資料：

| 平台 | 授權 | 自架 | 特點 |
|------|------|------|------|
| [Langfuse](https://langfuse.com/) | 開源 | ✓ | 最活躍的開源專案，16k+ stars |
| [Arize Phoenix](https://github.com/Arize-ai/phoenix) | 開源 | ✓ | Drift detection，Bias 偵測 |
| [LangSmith](https://www.langchain.com/langsmith) | 商業 | ✗ | 功能最完整 |
| [AgentOps](https://agentops.ai/) | 商業 | ✗ | 400+ 框架整合 |

### Langfuse 範例

```python
from langfuse import Langfuse
from langfuse.decorators import observe

langfuse = Langfuse()

@observe()
def my_agent(query: str):
    # 自動追蹤這個函數的執行
    response = llm.generate(query)
    return response
```

### 選擇建議

```
需要 Observability？
    │
    ├─ 必須自架？
    │       └─ YES → Langfuse
    │
    ├─ 已用 LangChain？
    │       └─ YES → LangSmith
    │
    └─ 重視開源生態？
            └─ YES → Phoenix
```

---

## 框架對比總表

:::tip
**表格說明**：✓ 表示「有支援」，✓✓✓ 表示「特別強」，✗ 表示「不支援」或「需要自己整合」。這是根據各框架文件與社群評價的主觀評估。
:::

| 維度 | LangSmith | Google ADK | Claude SDK | DeepEval | Inspect AI |
|------|-----------|------------|------------|----------|------------|
| **授權** | 商業 | 開源 | 開源 | 開源 | 開源 |
| **Tracing** | ✓✓✓ | ✓ | 需整合 | ✗ | ✓ |
| **內建 Metrics** | 多 | 中 | 無 | 50+ | 100+ |
| **Trajectory 評估** | ✓ | ✓✓✓ | 需整合 | ✓ | ✓ |
| **Multi-turn** | ✓✓✓ | ✓ | 需整合 | ✓ | ✓ |
| **Sandbox** | ✗ | ✗ | ✗ | ✗ | ✓✓✓ |
| **CI/CD 整合** | ✓ | ✓ | 需整合 | ✓✓✓ | ✓ |
| **學習曲線** | 低 | 中 | 低 | 低 | 中 |

---

## 思考題

<details>
<summary>Q1：為什麼 Claude SDK 選擇不內建評估功能？這是優點還是缺點？</summary>

**Anthropic 的考量**：
1. 評估需求因應用而異，一體適用的方案不存在
2. 避免與現有工具生態競爭
3. 專注於 SDK 核心功能

**優點**：
- 彈性選擇最適合的工具
- 不被單一生態系鎖定
- 可以組合多個工具

**缺點**：
- 需要自己整合
- 沒有「開箱即用」體驗
- 可能需要更多設定

這是一個 trade-off，適合有經驗的團隊。

</details>

<details>
<summary>Q2：什麼情況下你會選擇 Inspect AI 而不是 DeepEval？</summary>

**選 Inspect AI**：
- 評估涉及執行不信任的程式碼（需要 sandbox）
- 需要用現成的 benchmarks（SWE-bench、GAIA）
- 安全性評估是重點
- 學術研究或論文需要

**選 DeepEval**：
- 快速上手，類 pytest 語法
- 主要評估輸出品質而非安全性
- 想要整合進現有 CI/CD
- 不需要隔離執行環境

</details>

<details>
<summary>Q3：Golden Dataset 應該多大？如何維護？</summary>

**大小建議**：
- 初期：20-50 個高品質案例
- 穩定期：100-200 個涵蓋主要場景
- 不需要太大，品質比數量重要

**維護策略**：
1. **持續收集**：從生產環境抽取「完美」互動
2. **定期審查**：確保 golden cases 仍然代表期望行為
3. **版本控制**：與 Agent 版本一起管理
4. **覆蓋率追蹤**：確保覆蓋所有重要場景

**常見錯誤**：
- 只收集成功案例（應該也包含預期失敗的邊界情況）
- 長期不更新（Agent 能力改變後 golden dataset 可能過時）

</details>

## 小結

選擇評估工具的決策流程：

```
你的 Agent 框架？
    │
    ├─ LangChain/LangGraph → LangSmith（最省事）
    │
    ├─ Google Cloud → ADK + Vertex AI
    │
    ├─ Claude → SDK + Langfuse（開源）或 LangSmith（商業）
    │
    └─ 自研框架 → DeepEval（通用）或 Inspect AI（安全導向）
```

下一篇，我們會進入實作：如何把這些工具整合進 CI/CD，建立自動化的評估流程。

---

## 參考資料

- [LangSmith Documentation](https://docs.langchain.com/langsmith)
- [Google ADK Evaluation](https://google.github.io/adk-docs/evaluate/)
- [Claude Agent SDK Overview](https://platform.claude.com/docs/en/agent-sdk/overview)
- [DeepEval GitHub](https://github.com/confident-ai/deepeval)
- [Inspect AI](https://inspect.aisi.org.uk/)
- [Langfuse Documentation](https://langfuse.com/docs)
