# ADR-010: recordings Rules 権限モデル段階的強化設計

**Status**: Accepted（2026-04-24）
**Date**: 2026-04-24
**Supersedes**: Phase 0.5 原案（PR #115 / commit 25aa2a3、2026-04-23 に prod deploy → rollback）
**Related**: Issue #100、PR #180（Phase 0.5 rollback）、Codex plan review（本 PR）

## Context

Issue #100「Firestore Rules の recordings 権限が過剰（他人の録音を read/write/delete 可能）」を恒久解消する必要があった。

Phase 0.5 原案は `create` で `createdBy == request.auth.uid` を必須としたが、2026-04-23 19:25 JST の prod deploy で稼働中 iOS Build 35 と不整合を起こし permission-denied → **業務停止**（2h42m 後に rollback）。

### 稼働 iOS バイナリ（Build 35）の実挙動

PR #101（2026-04-20 merge）**以前**のコードは `FirestoreRecording.createdBy` に**空文字 (`""`) を保存**していた（Issue #99 / #101 参照）。2026-04-24 prod audit 実測:

```
tenant 279: 2 recordings, all createdBy="" (empty string)
```

Build 35 は App Store Unlisted 公開中、自社メンバーが実機使用中。iOS バージョンアップ（Build 36）経由で createdBy の書込みを修正する経路は、iOS レビュー + TestFlight 配布 + 実機受領の時間コストが大きく、根本解決を遅延させる。

### 前回の失敗から継承すべき教訓

1. rules-unit-tests 64 件では「旧 iOS × 新 Rules」= **実稼働中の組合せ**を検証できなかった
2. 実機 smoke test を「rules-unit-tests で代替」と判断した結果、Rules と稼働バイナリの整合検証が skip された
3. Codex review (前 PR #179) は docs 整合性のみの軽量スコープで、バイナリ整合に踏み込まなかった

## Decision

iOS バイナリを変更せず、**GCP 側 Rules のみで段階的に強化**する二段階権限モデルを採用する。

### 最終 Rules 設計（`firestore.rules` recordings block）

```firestore
match /recordings/{recordingId} {
  allow read: if isTenantMember(tenantId);

  allow create: if isTenantMember(tenantId)
    && (
      !('createdBy' in request.resource.data)
      || request.resource.data.createdBy == ''
      || request.resource.data.createdBy == request.auth.uid
    );

  allow update: if (
      isAdmin(tenantId)
      || (
        'createdBy' in resource.data
        && resource.data.createdBy == request.auth.uid
      )
    )
    && (
      // createdBy immutable (双方向 in-check、Evaluator HIGH 指摘対応):
      //   pre/post 双方で存在+等値、または双方で不在のいずれか。
      //   片側のみ存在 (client による追加 / FieldValue.delete() による削除) は全経路で deny。
      (
        'createdBy' in request.resource.data
        && 'createdBy' in resource.data
        && request.resource.data.createdBy == resource.data.createdBy
      )
      || (
        !('createdBy' in request.resource.data)
        && !('createdBy' in resource.data)
      )
    );

  allow delete: if isAdmin(tenantId)
    || (
      'createdBy' in resource.data
      && resource.data.createdBy == request.auth.uid
    );
}
```

### 設計原則

1. **createdBy の "存在" と "値" を条件分岐キー**として利用
2. **create は寛容**（省略 / 空文字 / auth.uid を全て許容、他人 uid / null / 型違いは deny）→ Build 35 互換性確保
3. **update/delete は厳格**（admin OR author 本人）+ **createdBy immutable**（admin を含む client 全経路で書換不可、所有権移管は Admin SDK Callable 経由のみ）
4. **read は暫定許容**（tenant member 全員可）→ 将来 Build で `RecordingList` query を createdBy で絞ってから段階強化する（将来版 ADR で reference）

### 動作マトリクス

| 操作 | 対象 | Build 35 (createdBy="") | 将来 Build N (createdBy==uid) |
|---|---|---|---|
| create | 自分の新規録音 | ✅ `""` 許容で通過 | ✅ `createdBy==uid` で通過 |
| read | 他人の録音 | ✅ tenant member 可 | ✅ 同左 |
| update | 自分の既存録音 | ⚠️ admin のみ可（`"" != uid`） | ✅ author 本人可 |
| update/delete | 他人の録音 | ❌ admin 以外遮断 | ❌ admin 以外遮断 |
| 改竄 | 他人 uid で create | ❌ deny | ❌ deny |
| 改竄 | author が createdBy 書換 update | ❌ immutable で deny | ❌ 同左 |

## Rationale

### 選定しなかった代替案

| 代替 | 却下理由 |
|------|---------|
| A. Build 36 リリース + Phase 0.5 再 deploy | iOS レビュー + TestFlight + 実機受領の総所要 2-5 日。業務停止状態の延長かつユーザー方針（iOS バージョンアップ回避）に反する |
| B. read も `createdBy == uid` に絞る | Firestore query の「全返却ドキュメントで read rule が通らないと query 失敗」仕様により、Build 35 の `RecordingList` query が即死 → 再び業務停止 |
| C. Cloud Function `onCreate` トリガーで createdBy を backfill | Firestore 2nd gen trigger は write 後発火のため、Rules で create を deny すると trigger 自体が発火しない（解決策にならない） |
| D. 既存 2 件 recordings を backfill script で修正 | admin 運用で十分カバー可能（自社単独フェーズ、実運用者 = admin）。backfill は副作用リスクがあり、scope を最小化 |

### 「read 暫定許容」の判断根拠

- 自社単独フェーズ（`@279279.net` ドメイン数名）で read 漏洩の脅威が限定的
- Firestore query の厳格な rule 適用仕様により、read 制限を先に入れると稼働バイナリが破綻
- Codex plan レビューでも「Go with conditions（暫定リスクとして docs 明記すれば可）」判定
- 将来 Build で iOS 側の query に `where('createdBy', '==', currentUid)` を追加してから、Rules の read を強化する段階計画

### 「backfill しない」の判断根拠

- prod audit 実測: 全 2 件（tenant 279）
- 実運用者 = admin なので、既存 2 件の update/delete は admin 権限で問題なく可能
- backfill 実装は audit log 遡及または手動判定が必要で、ROI が低い
- 将来的に backfill が必要になった場合は Admin SDK 経由の別スクリプトで one-off 実施可能

## Consequences

### 正の影響

- Issue #100 の最大リスク「他人の update / delete」が恒久解消
- Build 35 互換性を維持したまま prod deploy 可能
- iOS バージョンアップ不要で根本解決
- 将来 Build N+ で createdBy が正しく書かれるようになれば、author 制限が**自動的に**有効化（Rules 変更不要）

### 負の影響・トレードオフ

- **既存 createdBy="" recording は admin のみ update/delete 可**（自社単独フェーズでは業務影響ゼロだが、多ユーザー運用移行時に摩擦が発生しうる）
  - ただし admin は他フィールド (transcription, clientName 等) の update は可能。createdBy 自体の書き換えのみが admin 経路でも deny される（client 全経路で immutable、所有権移管は ADR-008 記載の Admin SDK 経由 Callable `transferOwnership` に限定）
- **read は tenant member 全員可のまま**（医療・介護相当データの相互可視性は将来 Build で段階強化）
- Build 35/N 混在期間はユーザー単位で挙動差（Build 35 作成分は admin のみ、Build N 作成分は author 本人 + admin）→ 将来 Build N リリース時に UI 説明 or backfill 計画が必要
- **`FieldValue.delete()` 経由の createdBy 削除**: Rules の双方向 in-check により deny されるが、`@firebase/rules-unit-testing` の merge 挙動差異により現状の unit test では直接検証不能。deny 保証は Rules 論理式（`!('createdBy' in request.resource.data) && !('createdBy' in resource.data)` の両方 false のみ PASS）で担保。

### 実測に基づく設計前提の検証

2026-04-24 prod audit (`node functions/scripts/audit-createdby.mjs carenote-prod-279`、read-only) 実測:

```
tenant 279:       total=2, empty=2, missing=0, non-empty=0
tenant demo-guest: total=0
```

既存 recordings は全 2 件とも `createdBy: ""` (string 型の空文字)。**非 string 型（null / number / map / array）の過去データ混入はゼロ**。これにより、Rules の `resource.data.createdBy == request.auth.uid` 比較で型不一致由来の silent 異常透過（silent-failure-hunter H1 指摘シナリオ）は実データ上では発生しないことを確認。将来 dev/prod audit で non-string 値が検出された場合は別途対応（defensive `is string` check の追加検討）。

### モニタリング

- prod deploy 後 10 min: Cloud Logging で `permission-denied` 急増がないこと
- dev/prod audit を四半期ごとに実行し createdBy 分布 + 型の変化を監視（`functions/scripts/audit-createdby.mjs`）
- 将来 Build N リリース時に audit で `non-empty` が増えたら read 制限段階強化の検討タイミング

## 再発防止プロトコル（Codex 観点 7 対応）

Phase 0.5 原案 rollback の教訓を構造化する。**「稼働中 iOS バイナリと新 Rules の組合せ検証」を rules-unit-tests で代替禁止**とする。

1. **Rules 変更 PR のテンプレート必須項目**（将来 PR で明文化予定）:
   - 前提 iOS build 番号（稼働中バイナリの特定）
   - Build 35 相当 payload × 新 Rules の unit test 追加
   - Build N 相当 payload × 新 Rules の unit test 追加
   - **iOS/クライアント側の該当操作実装有無の確認**（後述 §4）
2. **prod deploy 前の必須ゲート**（`docs/runbook/prod-deploy-smoke-test.md` § Phase 0.5.1 参照）:
   - rules-unit-tests 全件 PASS（今回 160/160、Phase 0.5 原案時 152 → +8 件新規 + 2 件反転）
   - dev rules deploy
   - **稼働バイナリ相当 iOS (dev 接続) で実機録音 CRUD smoke**（skip 禁止）
   - prod audit で createdBy 分布を baseline として記録
3. **「rules-unit-tests は実機 smoke の代替ではない」を明文化**（本 ADR と runbook）
4. **iOS 側クライアント実装の確認プロトコル**（本セッション 2026-04-24 smoke test 項目 5「delete できるはずが復活」の教訓から追加）:
   - Rules 許可/拒否の設計は、**実クライアントが当該操作を Firestore に送信して初めて意味を持つ**。未実装操作への Rules 設計は *false sense of safety* を生み、実害発生まで気づけない
   - Rules 変更前に以下を grep で確認:
     - `CareNote/Services/FirestoreService.swift` に該当操作のメソッドが存在するか（例: `deleteRecording`, `updateRecording`）
     - 該当 ViewModel で該当メソッドが呼ばれているか
     - collection に対する `.document(x).create()`/`.set()`/`.update()`/`.delete()` の grep ヒットがあるか
   - 未実装の場合の対応選択肢:
     - **(a)** iOS 実装を先に完了する PR を作成し、Rules PR の dependencies に含める
     - **(b)** 手動運用 / admin script を明文化する（ADR-009 Stage 1 pattern）
     - **(c)** Rules 変更と同時に iOS PR を作成する（1 release cycle で整合）
   - **本セッション (PR #181) の反省**: `recordings.document().delete()` が iOS 全コードベースに存在しない事実を事前検知できず、Phase 0.5.1 smoke test 項目 5 で初めて顕在化した。Issue #182 として別追跡化したが、本来は PR #181 と同時対応すべきだった

## 関連

- Issue #100（recordings 権限過剰）
- Issue #99（createdBy 空文字保存の regression、本 ADR の実データ前提の原因）
- PR #101（createdBy に uid を書く fix、Build 35 には未反映）
- PR #115（Phase 0.5 原案、2026-04-20 merge、2026-04-23 prod deploy → rollback）
- PR #180（Phase 0.5 rollback）
- [ADR-008 Account Ownership Transfer](./ADR-008-account-ownership-transfer.md) — `transferOwnership` Callable が本 ADR の client-side immutable 制約を bypass する唯一の正規経路（Admin SDK 経由で createdBy 書換）
- `docs/runbook/prod-deploy-smoke-test.md` § Phase 0.5.1
- `functions/test/firestore-rules.test.js` § `createdBy="" 既存レコード (Build 35 互換)`
- `functions/scripts/audit-createdby.mjs`（createdBy 分布の定期監査ツール）
