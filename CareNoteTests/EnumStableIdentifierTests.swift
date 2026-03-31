import Testing

@testable import CareNote

struct EnumStableIdentifierTests {
    // MARK: - OutputType

    @Test
    func outputTypeRawValuesAreEnglish() {
        #expect(OutputType.transcription.rawValue == "transcription")
        #expect(OutputType.visitRecord.rawValue == "visitRecord")
        #expect(OutputType.meetingMinutes.rawValue == "meetingMinutes")
        #expect(OutputType.summary.rawValue == "summary")
        #expect(OutputType.custom.rawValue == "custom")
    }

    @Test
    func outputTypeDisplayNamesAreJapanese() {
        #expect(OutputType.transcription.displayName == "文字起こし")
        #expect(OutputType.visitRecord.displayName == "訪問記録")
        #expect(OutputType.meetingMinutes.displayName == "会議録")
        #expect(OutputType.summary.displayName == "要約")
        #expect(OutputType.custom.displayName == "カスタム")
    }

    @Test
    func outputTypeFromLegacyConvertsAllCases() {
        #expect(OutputType.fromLegacy("文字起こし") == .transcription)
        #expect(OutputType.fromLegacy("訪問記録") == .visitRecord)
        #expect(OutputType.fromLegacy("会議録") == .meetingMinutes)
        #expect(OutputType.fromLegacy("要約") == .summary)
        #expect(OutputType.fromLegacy("カスタム") == .custom)
    }

    @Test
    func outputTypeFromLegacyReturnsNilForUnknown() {
        #expect(OutputType.fromLegacy("unknown") == nil)
        #expect(OutputType.fromLegacy("") == nil)
        #expect(OutputType.fromLegacy("transcription") == nil)
    }

    @Test
    func outputTypeFromLegacyRoundTrip() {
        for outputType in OutputType.allCases {
            let legacy = outputType.displayName
            #expect(OutputType.fromLegacy(legacy) == outputType)
        }
    }

    // MARK: - RecordingScene

    @Test
    func recordingSceneRawValuesAreEnglish() {
        #expect(RecordingScene.visit.rawValue == "visit")
        #expect(RecordingScene.meeting.rawValue == "meeting")
        #expect(RecordingScene.conference.rawValue == "conference")
        #expect(RecordingScene.intake.rawValue == "intake")
        #expect(RecordingScene.assessment.rawValue == "assessment")
        #expect(RecordingScene.other.rawValue == "other")
    }

    @Test
    func recordingSceneDisplayNamesAreJapanese() {
        #expect(RecordingScene.visit.displayName == "訪問")
        #expect(RecordingScene.meeting.displayName == "担当者会議")
        #expect(RecordingScene.conference.displayName == "カンファレンス")
        #expect(RecordingScene.intake.displayName == "インテーク")
        #expect(RecordingScene.assessment.displayName == "アセスメント")
        #expect(RecordingScene.other.displayName == "その他")
    }

    @Test
    func recordingSceneFromLegacyConvertsAllCases() {
        #expect(RecordingScene.fromLegacy("訪問") == .visit)
        #expect(RecordingScene.fromLegacy("担当者会議") == .meeting)
        #expect(RecordingScene.fromLegacy("カンファレンス") == .conference)
        #expect(RecordingScene.fromLegacy("インテーク") == .intake)
        #expect(RecordingScene.fromLegacy("アセスメント") == .assessment)
        #expect(RecordingScene.fromLegacy("その他") == .other)
    }

    @Test
    func recordingSceneFromLegacyReturnsNilForUnknown() {
        #expect(RecordingScene.fromLegacy("unknown") == nil)
        #expect(RecordingScene.fromLegacy("") == nil)
        #expect(RecordingScene.fromLegacy("visit") == nil)
    }

    @Test
    func recordingSceneFromLegacyRoundTrip() {
        for scene in RecordingScene.allCases {
            let legacy = scene.displayName
            #expect(RecordingScene.fromLegacy(legacy) == scene)
        }
    }

    @Test
    func recordingSceneDocumentTypePreserved() {
        #expect(RecordingScene.visit.documentType == "訪問記録")
        #expect(RecordingScene.meeting.documentType == "担当者会議録")
        #expect(RecordingScene.conference.documentType == "カンファレンス記録")
        #expect(RecordingScene.intake.documentType == "インテーク記録")
        #expect(RecordingScene.assessment.documentType == "アセスメント記録")
        #expect(RecordingScene.other.documentType == "記録")
    }
}
