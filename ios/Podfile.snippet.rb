# ios/Podfile 수정 사항
#
# 1) 맨 위의 platform 줄 주석을 풀고 13.0 이상으로 지정
platform :ios, '13.0'

# 2) 파일 맨 아래 post_install 블록을 아래처럼 교체
#    (permission_handler 는 iOS 에서 사용하지 않는 권한을 모두 비활성화해
#     App Store 심사 시 불필요한 권한 설명 요구를 피합니다.
#     이 앱은 iOS 에서 문서 선택기만 사용하므로 런타임 권한이 필요 없습니다.)
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_MEDIA_LIBRARY=0',
        'PERMISSION_MICROPHONE=0',
        'PERMISSION_CAMERA=0',
        'PERMISSION_PHOTOS=0',
        'PERMISSION_LOCATION=0',
        'PERMISSION_NOTIFICATIONS=0',
      ]
    end
  end
end
