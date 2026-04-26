@preconcurrency import FirebaseFunctions
import Foundation
import os.log

// MARK: - Value types

/// `transferOwnership` Cloud Function の counts/updated レスポンス。
/// 3 サブコレクション (recordings / templates / whitelist) の件数。
struct TransferOwnershipCounts: Sendable, Equatable {
    let recordings: Int
    let templates: Int
    let whitelist: Int
}

/// dryRun 呼出の戻り値。
struct TransferOwnershipDryRunResult: Sendable, Equatable {
    let dryRunId: String
    let counts: TransferOwnershipCounts
}

/// confirm 呼出の戻り値。
struct TransferOwnershipConfirmResult: Sendable, Equatable {
    let updated: TransferOwnershipCounts
}

// MARK: - Error

/// Cloud Function `transferOwnership` の HttpsError を UI 分岐可能な型へマップしたもの。
///
/// マッピング規則は `functions/src/transferOwnership.js` のエラーコード表 (ADR-008 Phase 1) に対応。
enum TransferOwnershipError: Error, Sendable, Equatable {
    /// ログイン未実施。
    case unauthenticated
    /// 非 admin が呼び出した。
    case permissionDenied
    /// caller の token に tenantId claim が無い等の前提崩れ。
    case failedPrecondition
    /// 引数欠落・型不正・`fromUid == toUid` 等。message は Cloud Function 側の文言。
    case invalidArgument(String)
    /// `dryRunId` 指定時に該当 doc が存在しない。
    case notFound
    /// 同じ `dryRunId` が既に running / completed (二重実行防止)。
    case alreadyExists
    /// Cloud Function 内部例外。message は Cloud Function 側の文言（あれば）。
    case `internal`(String?)
    /// レスポンス JSON の decode 失敗。
    case malformedResponse
    /// 想定外のエラー (ネットワーク / Functions 以外の domain 等)。
    case unknown(NSError)

    /// `Functions.functions().httpsCallable(...).call(...)` が throw した Error を
    /// 内部エラー型にマップする。`FunctionsErrorDomain` のもののみコード分類し、
    /// それ以外は `.unknown` で包む。
    static func map(_ error: Error) -> TransferOwnershipError {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain else {
            return .unknown(nsError)
        }
        let message = nsError.userInfo[NSLocalizedDescriptionKey] as? String
        switch nsError.code {
        case FunctionsErrorCode.unauthenticated.rawValue:
            return .unauthenticated
        case FunctionsErrorCode.permissionDenied.rawValue:
            return .permissionDenied
        case FunctionsErrorCode.failedPrecondition.rawValue:
            return .failedPrecondition
        case FunctionsErrorCode.invalidArgument.rawValue:
            return .invalidArgument(message ?? "")
        case FunctionsErrorCode.notFound.rawValue:
            return .notFound
        case FunctionsErrorCode.alreadyExists.rawValue:
            return .alreadyExists
        case FunctionsErrorCode.internal.rawValue:
            return .internal(message)
        default:
            return .unknown(nsError)
        }
    }

    /// `.unknown(NSError)` の同値判定は domain + code のみで行う (userInfo は含めない)。
    /// userInfo は呼出毎に異なるメタ情報 (タイムスタンプ等) を含みうるため、
    /// 比較対象に入れると同じエラー種別が偽陽性で differ 扱いになる。
    static func == (lhs: TransferOwnershipError, rhs: TransferOwnershipError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthenticated, .unauthenticated),
             (.permissionDenied, .permissionDenied),
             (.failedPrecondition, .failedPrecondition),
             (.notFound, .notFound),
             (.alreadyExists, .alreadyExists),
             (.malformedResponse, .malformedResponse):
            return true
        case let (.invalidArgument(l), .invalidArgument(r)):
            return l == r
        case let (.internal(l), .internal(r)):
            return l == r
        case let (.unknown(l), .unknown(r)):
            return l.domain == r.domain && l.code == r.code
        default:
            return false
        }
    }
}

// MARK: - Protocol

/// `transferOwnership` Cloud Function を呼び出す抽象化。
/// テスト容易性のために protocol にする (ViewModel は具象 SDK に依存しない)。
protocol TransferOwnershipServicing: Sendable {
    func dryRun(fromUid: String, toUid: String) async throws -> TransferOwnershipDryRunResult
    func confirm(dryRunId: String) async throws -> TransferOwnershipConfirmResult
}

// MARK: - Firebase Functions impl

/// `Functions.functions(region:).httpsCallable("transferOwnership")` への薄い wrapper。
/// リージョン・callable 名は ADR-008 / `functions/src/transferOwnership.js` の REGION / export と一致。
final class TransferOwnershipService: TransferOwnershipServicing, Sendable {
    private static let logger = Logger(subsystem: "jp.carenote.app", category: "TransferOwnershipService")
    private static let callableName = "transferOwnership"
    private static let defaultRegion = "asia-northeast1"
    private let region: String

    init(region: String = TransferOwnershipService.defaultRegion) {
        self.region = region
    }

    func dryRun(fromUid: String, toUid: String) async throws -> TransferOwnershipDryRunResult {
        let functions = Functions.functions(region: region)
        let payload: [String: Any] = [
            "fromUid": fromUid,
            "toUid": toUid,
            "dryRun": true,
        ]
        let response: HTTPSCallableResult
        do {
            response = try await functions.httpsCallable(Self.callableName).call(payload)
        } catch {
            Self.logger.error("transferOwnership dryRun failed: \(error.localizedDescription, privacy: .public)")
            throw TransferOwnershipError.map(error)
        }
        guard let dict = response.data as? [String: Any],
              let dryRunId = dict["dryRunId"] as? String,
              let counts = Self.parseCounts(dict["counts"])
        else {
            Self.logger.error("transferOwnership dryRun returned malformed response")
            throw TransferOwnershipError.malformedResponse
        }
        return TransferOwnershipDryRunResult(dryRunId: dryRunId, counts: counts)
    }

    func confirm(dryRunId: String) async throws -> TransferOwnershipConfirmResult {
        let functions = Functions.functions(region: region)
        let payload: [String: Any] = ["dryRunId": dryRunId]
        let response: HTTPSCallableResult
        do {
            response = try await functions.httpsCallable(Self.callableName).call(payload)
        } catch {
            Self.logger.error("transferOwnership confirm failed: \(error.localizedDescription, privacy: .public)")
            throw TransferOwnershipError.map(error)
        }
        guard let dict = response.data as? [String: Any],
              let updated = Self.parseCounts(dict["updated"])
        else {
            Self.logger.error("transferOwnership confirm returned malformed response")
            throw TransferOwnershipError.malformedResponse
        }
        return TransferOwnershipConfirmResult(updated: updated)
    }

    /// JSON 由来の `Any` から `TransferOwnershipCounts` を取り出す。
    /// 数値は NSNumber 経由で来うるため `Int` 強制 cast を介する。
    private static func parseCounts(_ value: Any?) -> TransferOwnershipCounts? {
        guard let dict = value as? [String: Any],
              let recordings = (dict["recordings"] as? NSNumber)?.intValue,
              let templates = (dict["templates"] as? NSNumber)?.intValue,
              let whitelist = (dict["whitelist"] as? NSNumber)?.intValue
        else {
            return nil
        }
        return TransferOwnershipCounts(recordings: recordings, templates: templates, whitelist: whitelist)
    }
}
