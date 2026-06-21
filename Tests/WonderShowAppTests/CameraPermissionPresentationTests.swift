@testable import WonderShow
@testable import WonderShowApp
import Testing

@Test func cameraPermissionPresentationSeparatesCameraFromAccessibility() {
    let copy = AppLocalization().copy(for: .zhHans)

    #expect(CameraPermissionPresentation.statusText(for: .authorized, copy: copy) == "已授权")
    #expect(CameraPermissionPresentation.statusText(for: .notDetermined, copy: copy) == "需要授权")
    #expect(CameraPermissionPresentation.statusText(for: .denied, copy: copy) == "已拒绝")
    #expect(CameraStatus.permissionDenied.primaryActionTitle(copy: copy) == "摄像头权限")
    #expect(CameraStatus.permissionDenied.recoveryHint(copy: copy) == "请在系统设置中允许灵演访问摄像头。")
}

@Test func cameraPermissionPresentationKeepsLocalizedLabelsAvailable() {
    let traditional = AppLocalization().copy(for: .zhHant)
    let english = AppLocalization().copy(for: .en)

    #expect(CameraPermissionPresentation.statusText(for: .restricted, copy: traditional) == "受限制")
    #expect(CameraStatus.permissionDenied.primaryActionTitle(copy: traditional) == "攝影機權限")
    #expect(CameraPermissionPresentation.statusText(for: .denied, copy: english) == "Denied")
    #expect(CameraStatus.permissionDenied.primaryActionTitle(copy: english) == "Camera Access")
}
