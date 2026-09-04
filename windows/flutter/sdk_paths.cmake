# Add Windows SDK include paths for ATL
set(WINDOWS_SDK_PATH "C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0")
if(EXISTS "${WINDOWS_SDK_PATH}")
  set(CMAKE_INCLUDE_PATH "${CMAKE_INCLUDE_PATH};${WINDOWS_SDK_PATH}/um;${WINDOWS_SDK_PATH}/shared")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /I\"${WINDOWS_SDK_PATH}/um\" /I\"${WINDOWS_SDK_PATH}/shared\"")
endif()
