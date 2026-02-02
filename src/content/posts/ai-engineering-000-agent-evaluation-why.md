---
title: 為什麼需要評估 AI Agent？
description: 從傳統軟體測試到 Agent 評估的挑戰，理解評估機制的核心概念與學術研究基礎
date: 2026-02-02
slug: ai-engineering-000-agent-evaluation-why
series: "ai-engineering"
tags:
  - "ai-engineering"
  - "agent"
  - "evaluation"
  - "note"
---

:::note
**本文適合的讀者**

- 有基本程式開發經驗
- 聽過 ChatGPT、Claude 等 AI 工具
- 想了解如何評估 AI 應用的品質

如果你完全不熟悉 LLM，建議先閱讀下方的「什麼是 LLM Agent？」章節。
:::

當你部署一個 LLM Agent 到生產環境，你怎麼知道它「夠好」？這個問題比想像中複雜得多。

## 什麼是 LLM Agent？

在深入評估之前，先快速釐清這兩個核心概念：

**LLM（Large Language Model，大型語言模型）** 是像 ChatGPT、Claude、Gemini 這類 AI 模型。它們能理解自然語言、生成文字回應，但本質上只是「給輸入、產輸出」的函數——你問它問題，它給你答案。

**Agent（代理人）** 則是在 LLM 之上加了「自主行動」的能力。Agent 不只是回答問題，它可以：
- **規劃**：把複雜任務拆解成步驟
- **使用工具**：呼叫 API、查資料庫、執行程式碼
- **迭代**：根據結果調整下一步行動

簡單比喻：
- **LLM** 像是一個很聰明的顧問，你問什麼它答什麼
- **Agent** 像是一個助理，你交代任務後它會自己想辦法完成

```
你：「幫我查一下明天台北的天氣」

LLM：「我無法查詢即時天氣，建議你使用天氣 App...」

Agent：
  1. 理解用戶想知道天氣
  2. 呼叫天氣 API → 取得資料
  3. 回覆：「明天台北多雲，氣溫 18-24°C，建議帶薄外套」
```

這個「自己想辦法」的過程，就是 Agent 評估的核心挑戰。

## 傳統測試 vs Agent 評估

傳統軟體測試建立在一個簡單的前提：**相同輸入產生相同輸出**。你寫一個函數，給它固定的參數，預期得到固定的結果。

```python
def add(a, b):
    return a + b

assert add(2, 3) == 5  # 永遠成立
```

但 LLM Agent 打破了這個前提：

| 傳統軟體 | LLM Agent |
|----------|-----------|
| 確定性輸出 | 非確定性輸出（同樣的問題可能得到不同答案） |
| 單一函數呼叫 | 多步驟推理鏈（會自己決定執行哪些步驟） |
| 明確的成功/失敗 | 品質是光譜（答案可能「部分正確」） |
| 獨立執行 | 與外部工具互動（呼叫 API、資料庫等） |

:::tip
**為什麼 LLM 輸出是「非確定性」的？**

LLM 生成文字時會加入隨機性（temperature 參數），讓回應更自然多樣。即使同樣的問題，每次執行可能得到措辭不同的答案。這和傳統程式「1+1 永遠等於 2」的確定性完全不同。
:::

### 一個具體的例子

假設你有一個 Agent 負責回答客戶問題。用戶問：「我的訂單在哪裡？」

**傳統系統**：查詢資料庫 → 回傳訂單狀態 → 結束

**LLM Agent 可能的執行路徑**：
1. 理解用戶意圖
2. 決定需要查詢訂單系統
3. 呼叫 `get_order_status` 工具（這就是所謂的「工具」——Agent 可以呼叫的外部 API 或函數）
4. 解讀回傳結果
5. 組織回應
6. 可能還會主動問：「需要我幫你聯繫物流嗎？」

每一步都可能出錯，而且「出錯」的定義本身就很模糊——Agent 多問一句是「貼心」還是「囉嗦」？

:::info
**什麼是「工具」？**

在 Agent 的世界裡，「工具（Tool）」是 Agent 可以呼叫的外部功能，例如：
- 查詢資料庫的 API
- 發送 Email 的函數
- 搜尋引擎
- 計算機

Agent 的核心能力之一，就是「知道什麼時候該用哪個工具」。
:::

## Agent 評估的四個維度

根據 [KDD 2025 的綜述論文](https://arxiv.org/abs/2507.21504)，Agent 評估可以分成四個維度：

### 1. 行為（Behavior）

用戶可見的最終表現：
- **Task Success Rate**：任務完成率
- **Output Quality**：回應品質

這是最直覺的指標——Agent 有沒有完成用戶交代的事？

### 2. 能力（Capabilities）

Agent 達成目標的「過程」：
- **Tool Selection Accuracy**：選對工具的比例
- **Parameter Correctness**：參數正確率
- **Reasoning Quality**：推理邏輯是否合理

即使最終結果正確，過程也很重要。一個靠運氣猜對答案的 Agent 和一個邏輯清晰的 Agent，可靠性天差地別。

### 3. 可靠性（Reliability）

跨多次執行的一致性：
- **pass@k**：k 次嘗試中至少成功一次（例：pass@3 表示 3 次內成功就算過）
- **pass^k**：k 次嘗試全部成功（例：pass^3 表示 3 次都要成功才算過，更嚴格）
- **Robustness**：對輸入變化的穩定性

這兩個指標來自學術論文，是 AI 領域的標準術語。`@` 代表「至少一次」，`^` 代表「每次都要」。

一個 Agent 如果 10 次執行有 3 次失敗，即使成功率 70%，在生產環境可能也不可接受。

### 4. 安全性（Safety）

倫理與合規：
- **Toxicity**：有害內容偵測
- **Bias**：偏見檢測
- **Compliance**：法規遵循

這在企業環境尤其重要——你的 Agent 會不會洩露敏感資訊？會不會產生歧視性內容？

## 評估的三種方法

知道要評估什麼之後，下一個問題是「怎麼評估」：

### Code-based 評估

用程式碼定義規則：

```python
def eval_response(response):
    # 檢查是否包含必要資訊
    if "訂單編號" not in response:
        return 0
    # 檢查格式
    if len(response) > 500:
        return 0.5
    return 1.0
```

**優點**：確定性、可重現、快速
**缺點**：只能處理可規則化的情況，無法評估開放式任務

### LLM-as-Judge

用另一個 LLM 來評估輸出：

```python
judge_prompt = """
評估以下 Agent 回應的品質（1-5 分）：

用戶問題：{user_query}
Agent 回應：{agent_response}

評分標準：
- 準確性：資訊是否正確
- 完整性：是否回答了所有問題
- 語氣：是否專業友善
"""
```

**優點**：可擴展、能處理主觀判斷、支援複雜評估
**缺點**：評估結果可能變異、成本較高

### Human-in-the-Loop

人工評估：

**優點**：Gold standard（最權威的參考標準），最接近真實用戶體驗
**缺點**：昂貴、難以規模化、評估者之間可能不一致

### 實務上的組合

大多數團隊會組合使用：

```
開發階段 → Code-based（快速迭代）
         ↓
測試階段 → LLM-as-Judge（規模化評估）
         ↓
上線前   → Human Review（抽樣驗證）
         ↓
生產環境 → 自動監控 + 用戶回饋
```

## Trajectory vs Output：兩種評估視角

這是 Agent 評估最重要的區分之一。

**Trajectory（軌跡）** 是 Agent 執行過程中的每一個步驟記錄——它選了哪些工具、傳了什麼參數、按什麼順序執行。這個術語在 AI Agent 領域被廣泛使用，因為 Agent 的行為就像是在「行動空間」中走出一條軌跡。

### Output 評估

只看最終結果：

```
輸入：「幫我訂明天下午 3 點的會議室」
輸出：「已為您預訂 A301 會議室，明天下午 3:00-4:00」

評估：✓ 完成任務
```

### Trajectory 評估

檢視執行過程：

```
Step 1: 解析需求 → 「明天下午 3 點，會議室」
Step 2: 呼叫 check_availability(date="2024-01-16", time="15:00")
Step 3: 收到可用會議室列表 [A301, B205, C102]
Step 4: 呼叫 book_room(room="A301", date="2024-01-16", time="15:00")
Step 5: 收到確認
Step 6: 組織回應

評估：
- 工具選擇 ✓
- 參數正確 ✓
- 執行順序 ✓
- 最終結果 ✓
```

**為什麼 Trajectory 重要？**

1. **Debug 更容易**：知道哪一步出錯
2. **發現潛在問題**：即使結果對了，過程可能有隱患
3. **效率優化**：找出不必要的步驟

[TRAJECT-Bench](https://www.emergentmind.com/topics/traject-bench) 就是專門針對 Trajectory 評估設計的 benchmark，它檢查：
- 工具選擇是否正確
- 參數是否符合 schema
- 執行順序是否合理
- 依賴關係是否滿足

## 學術研究的核心 Benchmarks

**Benchmark（基準測試）** 是一組標準化的測試任務，用來衡量不同 Agent 的能力。就像學測是評估學生能力的標準，benchmark 是評估 AI Agent 的標準。

如果你想了解 Agent 能力的絕對水平，這些 benchmarks 是重要參考：

| Benchmark | 領域 | 特點 |
|-----------|------|------|
| [WebArena](https://webarena.dev/) | Web 導航 | 真實網站互動 |
| [SWE-bench](https://www.swebench.com/) | 軟體工程 | 修復真實 GitHub issue |
| [GAIA](https://huggingface.co/gaia-benchmark) | 通用 Agent | 多步驟推理 |
| [ToolBench](https://github.com/OpenBMB/ToolBench) | Tool 使用 | 16,000+ 真實 API |
| [AgentBench](https://github.com/THUDM/AgentBench) | 綜合 | 8 種環境 |

這些 benchmarks 的共同特點：
- 任務來自真實場景
- 需要多步驟推理
- 涉及與外部系統互動
- 有明確的成功標準

## 思考題

<details>
<summary>Q1：為什麼 pass^k 比 pass@k 更嚴格？什麼場景下你會選擇用 pass^k？</summary>

**pass@k**：k 次嘗試中只要成功一次就算通過
**pass^k**：k 次嘗試必須全部成功

pass^k 更嚴格是因為它要求 100% 一致性。

**使用場景**：
- 金融交易處理（不能有任何失敗）
- 醫療建議系統（每次都要正確）
- 安全關鍵應用

如果你的 Agent 允許偶爾失敗後重試，pass@k 就足夠；如果失敗代價很高，用 pass^k。

</details>

<details>
<summary>Q2：LLM-as-Judge 的主要風險是什麼？如何緩解？</summary>

**主要風險**：
1. **一致性問題**：同一個輸入可能得到不同評分
2. **偏見**：Judge LLM 可能有自己的偏好
3. **自我偏袒**：用 GPT-4 評估 GPT-4 的輸出可能過於寬容

**緩解方法**：
1. 使用結構化評分標準（rubric）
2. 多次評估取平均
3. 使用不同的 Judge LLM
4. 定期用人工評估校準

</details>

<details>
<summary>Q3：Output 評估通過但 Trajectory 評估失敗，代表什麼？</summary>

這代表 Agent「歪打正著」——結果對了，但過程有問題。

**可能的情況**：
- 呼叫了不必要的工具（效率問題）
- 用錯誤的推理得到正確結論（可靠性隱患）
- 違反了安全政策但結果符合預期

**為什麼危險**：這類 Agent 在簡單情況下看起來正常，但在複雜或邊界情況下容易出錯。

</details>

## 小結

Agent 評估不是「測試」的升級版，而是一個全新的領域：

1. **非確定性**是核心挑戰，需要統計方法
2. **多維度**評估（行為、能力、可靠性、安全性）
3. **過程和結果**同樣重要
4. **組合多種方法**才能全面評估

下一篇文章，我們會深入各個框架（LangSmith、Google ADK、Claude SDK）如何實現這些評估機制。

---

## 參考資料

- [Evaluation and Benchmarking of LLM Agents: A Survey (KDD 2025)](https://arxiv.org/abs/2507.21504)
- [TRAJECT-Bench: LLM Tool-Use Benchmark](https://www.emergentmind.com/topics/traject-bench)
- [AgentBench: Evaluating LLMs as Agents](https://arxiv.org/abs/2308.03688)
- [LLM Agent Evaluation: Complete Guide - Confident AI](https://www.confident-ai.com/blog/llm-agent-evaluation-complete-guide)
