import SwiftUI

extension SettingsView {
    @ViewBuilder
    var exportCards: some View {
        if cardMatches(title: "출력 설정", keywords: ["PDF", "중앙정렬식", "한국식", "폰트", "정렬", "export"]) {
            exportSettingsCard
        }
    }

    @ViewBuilder
    var dataBackupCards: some View {
        if cardMatches(title: "데이터 저장소", keywords: ["작업 파일", "workspace", "저장 경로"]) {
            workspaceCard
        }
        if cardMatches(title: "자동 백업", keywords: ["백업", "보관", "zip", "backup"]) {
            autoBackupCard
        }
    }

    @ViewBuilder
    var aboutLegalCards: some View {
        if cardMatches(title: "앱 정보", keywords: ["버전", "정보", "about"]) {
            settingsCard(title: "앱 정보") {
                Text("앱 버전: \(appVersionLabel)")
                    .font(.system(size: 11, design: .monospaced))
                Text("이 화면의 설정은 변경 즉시 저장됩니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if cardMatches(title: "폰트 라이선스 (OFL)", keywords: ["라이선스", "법적", "폰트", "ofl"]) {
            oflFontLicenseCard
        }
    }

    var exportSettingsCard: some View {
        settingsCard(title: "출력 설정") {
            VStack(alignment: .leading, spacing: 8) {
                Text("중앙정렬식 PDF")
                    .font(.subheadline.weight(.semibold))
                Text("폰트 크기: \(String(format: "%.1f", storage.exportCenteredFontSize))pt")
                Slider(value: storage.$exportCenteredFontSize, in: 8...20, step: 0.5)
                Toggle("헤딩 볼드", isOn: storage.$exportCenteredSceneHeadingBold)
                Toggle("캐릭터 볼드", isOn: storage.$exportCenteredCharacterBold)
                Toggle("오른쪽 씬 번호 표시", isOn: storage.$exportCenteredShowRightSceneNumber)

                Divider()

                Text("한국식 PDF")
                    .font(.subheadline.weight(.semibold))
                Text("폰트 크기: \(String(format: "%.1f", storage.exportKoreanFontSize))pt")
                Slider(value: storage.$exportKoreanFontSize, in: 8...20, step: 0.5)
                Toggle("씬 헤딩 볼드", isOn: storage.$exportKoreanSceneBold)
                Toggle("캐릭터 볼드", isOn: storage.$exportKoreanCharacterBold)
                Picker("캐릭터 정렬", selection: storage.$exportKoreanCharacterAlignment) {
                    Text("오른쪽")
                        .tag("right")
                    Text("왼쪽")
                        .tag("left")
                }
                .pickerStyle(.segmented)
            }
        }
    }

    var workspaceCard: some View {
        settingsCard(title: "데이터 저장소") {
            Text("현재 저장 경로")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(currentStoragePath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            Button("기존 작업 파일 열기...") {
                openWorkspaceFile()
            }

            Button("새 작업 파일 만들기...") {
                createWorkspaceFile()
            }

            Button("작업 파일 초기화 (다시 선택)", role: .destructive) {
                pendingConfirmation = .resetWorkspace
            }
        }
    }

    var autoBackupCard: some View {
        settingsCard(title: "자동 백업") {
            Toggle("앱 종료 시 자동 백업", isOn: storage.$autoBackupEnabledOnQuit)

            Text("백업 폴더")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(currentAutoBackupPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            HStack(spacing: 8) {
                Button("백업 폴더 선택...") {
                    selectAutoBackupDirectory()
                }
                .disabled(!storage.autoBackupEnabledOnQuit)

                Button("기본 위치로") {
                    storage.autoBackupDirectoryPath = WorkspaceAutoBackupService.defaultBackupDirectoryURL().path
                    setAutoBackupStatus("기본 백업 경로를 적용했습니다.", isError: false)
                }
                .disabled(!storage.autoBackupEnabledOnQuit)
            }

            if !storage.autoBackupEnabledOnQuit {
                Text("자동 백업이 꺼져 있어 폴더 설정은 백업 활성화 후 적용됩니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("보관 정책: 최신 10개 + 이후 일 1개(7일) + 주 1개(4주까지) + 이후 월 1개")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(3)

            Text("백업 파일명: 작업이름-YYYY-MM-DD-HH-mm-ss.wtf.zip")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)

            Text("압축 해제 시 작업이름.wtf 컨테이너로 복원됩니다.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)

            if let message = autoBackupStatusMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(autoBackupStatusIsError ? .red : .secondary)
                    .lineLimit(2)
            }
        }
    }

    var appVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(version) (\(build))"
    }

    @ViewBuilder
    var oflFontLicenseCard: some View {
        settingsCard(title: "폰트 라이선스 (OFL)") {
            Text("앱에 포함된 아래 폰트 파일은 SIL Open Font License 1.1 조건으로 배포됩니다.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(oflFontFiles, id: \.self) { fileName in
                    Text(fileName)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Link("OFL 공식 전문 열기", destination: oflLicenseURL)
                .font(.system(size: 11))

            DisclosureGroup("라이선스 전문 보기") {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(oflLicenseText)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 130, maxHeight: 220)
                .padding(.top, 4)
            }
            .font(.system(size: 11))
        }
    }

    var oflLicenseText: String {
        """
        SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007

        PREAMBLE
        The goals of the Open Font License (OFL) are to stimulate worldwide development
        of collaborative font projects, to support the font creation efforts of academic
        and linguistic communities, and to provide a free and open framework in which
        fonts may be shared and improved in partnership with others.

        The OFL allows the licensed fonts to be used, studied, modified and redistributed
        freely as long as they are not sold by themselves. The fonts, including any
        derivative works, can be bundled, embedded, redistributed and/or sold with any
        software provided that any reserved names are not used by derivative works. The
        fonts and derivatives, however, cannot be released under any other type of
        license. The requirement for fonts to remain under this license does not apply
        to any document created using the fonts or their derivatives.

        DEFINITIONS
        "Font Software" refers to the set of files released by the Copyright Holder(s)
        under this license and clearly marked as such. This may include source files,
        build scripts and documentation.

        "Reserved Font Name" refers to any names specified as such after the copyright
        statement(s).

        "Original Version" refers to the collection of Font Software components as
        distributed by the Copyright Holder(s).

        "Modified Version" refers to any derivative made by adding to, deleting, or
        substituting -- in part or in whole -- any of the components of the Original
        Version, by changing formats or by porting the Font Software to a new environment.

        "Author" refers to any designer, engineer, programmer, technical writer or other
        person who contributed to the Font Software.

        PERMISSION & CONDITIONS
        Permission is hereby granted, free of charge, to any person obtaining a copy
        of the Font Software, to use, study, copy, merge, embed, modify, redistribute,
        and sell modified and unmodified copies of the Font Software, subject to the
        following conditions:

        1) Neither the Font Software nor any of its individual components, in Original
           or Modified Versions, may be sold by itself.

        2) Original or Modified Versions of the Font Software may be bundled,
           redistributed and/or sold with any software, provided that each copy contains
           the above copyright notice and this license. These can be included either as
           stand-alone text files, human-readable headers or in the appropriate
           machine-readable metadata fields within text or binary files as long as those
           fields can be easily viewed by the user.

        3) No Modified Version of the Font Software may use the Reserved Font Name(s)
           unless explicit written permission is granted by the corresponding Copyright
           Holder. This restriction only applies to the primary font name as presented
           to the users.

        4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font Software
           shall not be used to promote, endorse or advertise any Modified Version,
           except to acknowledge the contribution(s) of the Copyright Holder(s) and the
           Author(s) or with their explicit written permission.

        5) The Font Software, modified or unmodified, in part or in whole, must be
           distributed entirely under this license, and must not be distributed under any
           other license. The requirement for fonts to remain under this license does not
           apply to any document created using the Font Software.

        TERMINATION
        This license becomes null and void if any of the above conditions are not met.

        DISCLAIMER
        THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF MERCHANTABILITY, FITNESS
        FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF COPYRIGHT, PATENT, TRADEMARK, OR
        OTHER RIGHT. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM,
        DAMAGES OR OTHER LIABILITY, INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL,
        OR CONSEQUENTIAL DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
        ARISING FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM OTHER
        DEALINGS IN THE FONT SOFTWARE.
        """
    }
}
