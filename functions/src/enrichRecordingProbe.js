// enrichRecordingProbe: 一時的な dev 専用 probe trigger
//
// 目的: Firestore Gen 2 auth context trigger で iOS SDK 経由の認証ユーザー
// 書き込みが authType/authId として取れるか実測する。
//
// 実測結果に基づいて Phase 0.5 Rules 再設計を決定する（ADR-010 予定）:
// - authType=="app_user" かつ authId==uid → Cloud Functions trigger による
//   createdBy 自動付与が信頼可能 → iOS 更新ゼロで完全 security を実現できる
// - authType=="unknown" / authId が欠落・email 等 → 方向 1 は断念、方向 3
//   （Rules の段階的緩和）で部分的解決に留める必要がある
//
// 本 probe は log 出力のみで副作用なし（Firestore への書き戻しなし）。
// 測定完了後に削除する。

const { onDocumentCreatedWithAuthContext } = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");

exports.enrichRecordingProbe = onDocumentCreatedWithAuthContext(
  {
    document: "tenants/{tenantId}/recordings/{recordingId}",
    region: "asia-northeast1",
  },
  (event) => {
    const data = event.data?.data() ?? {};
    logger.info("ENRICH_PROBE", {
      authType: event.authType ?? null,
      authId: event.authId ?? null,
      tenantId: event.params?.tenantId,
      recordingId: event.params?.recordingId,
      dataHasCreatedBy: "createdBy" in data,
      dataCreatedByValue: data.createdBy ?? null,
      eventId: event.id,
      eventTime: event.time,
    });
  }
);
