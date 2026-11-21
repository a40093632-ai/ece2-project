# 1차 구현 정리

## 구현 범위

STM32는 내부 RTC 시각을 유지하고 초가 바뀔 때 PC로 HH:MM:SS를 출력한다. FPGA는 스톱워치와 상대시간 예약 제어를 각각 구현하고, 통합 top에서 버튼과 8자리 표시를 연결했다.

| 구분 | 구현한 동작 | 검증 결과 |
| --- | --- | --- |
| STM32 시계 | 내부 RTC, 초 변경 시 USART2 출력 | 시작 어셈블리 포함 30개 소스 ARM 컴파일 오류 0개 |
| 스톱워치 | 시작·일시정지·재개·초기화, MM:SS.cc 표시 | 기존 테스트벤치 PASS |
| 예약 제어 | 5초 대기 → 10초 ON → OFF, 취소·중복 시작 방지 | 160개 자기검사 PASS |
| FPGA 통합 | 모드 전환, 시작 입력 배분, 공통 취소·표시 선택 | 14개 통합 검사 PASS |

시뮬레이션은 Icarus Verilog의 SystemVerilog 모드로 실행했다. 기능별 사진과 조원이 제공한 증빙은 evidence에 있다. 검토 중 생성한 원본 로그와 VCD는 로컬에서 관리한다.

## 프로젝트 구조

| 폴더 | 용도 |
| --- | --- |
| mcu/main_project | 실제 STM32 개발·빌드 프로젝트 |
| mcu/examples | 조교 C 참고 예제 |
| fpga/stopwatch | 스톱워치 단독 시험 |
| fpga/scheduler | 예약 제어 단독 시험 |
| fpga/system | 통합 top·테스트벤치·XDC·전체 작업용 워크스페이스 |
| fpga/examples | 조교 FPGA 참고 예제 |
| evidence | 기능별 사진·화면 캡처와 조원 증빙 |
| docs/first_implementation.md | 현재 1차 구현과 확인할 사항 |

common 폴더는 사용하지 않는다. 단독 시험은 각자의 소스를 사용한다. 통합 프로젝트는 stopwatch/src의 공통 버튼·분주·표시 모듈 한 벌, stopwatch.v, scheduler.v와 system/src/top.v를 명시적으로 등록한다. 동일한 이름의 모듈이 중복 등록되지 않도록 각 프로젝트의 소스 목록을 따른다.

## FPGA 핀과 동작

장치는 Combo II-DLD S75의 xc7s75fgga484-1이다. 클록 B6의 실제 입력은 보드의 CLOCK SELECT SWITCH를 조절해 표시창 50과 MHz 표시를 확인한다. XDC의 20ns 클록과 코드 CLK_HZ=50,000,000이 일치한다. KEYPADS SEL은 버튼 모드로 맞춘다.

| 신호 | 핀 | 역할 |
| --- | --- | --- |
| clk_50mhz | B6 | 보드에서 선택한 MAIN CLOCK1 |
| rst_p | K4 | 버튼1, 전체 리셋 |
| btn_start | N8 | 버튼2, 현재 모드의 시작/일시정지 또는 예약 시작 |
| btn_clear | N4 | 버튼3, 예약 취소 및 스톱워치 초기화 |
| btn_mode | N1 | 버튼4, 스톱워치/예약 화면 전환 |
| led_run | N5 | LED8, 예약 load_en 상태 |

버튼과 LED 핀은 앞서 제공한 책의 핀 표와 일치한다. 버튼은 눌렀을 때 HIGH이며 2단 동기화·20ms 디바운스를 거친다. 표시 모드를 바꿔도 실행 중인 기능은 계속 진행한다. 버튼3은 모든 모드에서 예약을 취소한다. 버튼1은 두 기능을 모두 초기화한다. 이 모드·버튼 배분은 1차 통합 시험을 위한 설정이다.

세그먼트 데이터 [0..7]은 H2/J7/J3/J1/E4/E2/F5/F1, 자리 선택 [0..7]은 K5/K3/K1/L6/G3/G1/H6/H4다. 기존 스톱워치 XDC와 모두 일치하며 중복 핀 배정은 없다. 코드상 세그먼트 데이터는 active-high, 자리 선택은 active-low다. 현재 확보한 자료에서 세그먼트 핀의 독립적인 책 원본 대조는 완료하지 못했다. 실제 보드에서 숫자·자리 방향·소수점 위치를 확인한다.

현재 출력은 LED8로 확인한다. MOSFET 게이트로 내보내는 외부 BDIO와 UART의 FPGA 핀은 아직 배정하지 않았다. N5는 온보드 LED 연결 핀이므로 외부 BDIO 연결 위치로 간주하지 않는다. BDIO 버스 스위치 활성 상태와 실측 HIGH 전압을 확인한 뒤 별도 외부 출력을 추가한다.

## MCU 설정

STM32G474RE의 내부 RTC를 레지스터로 설정한다. 보드 LSE 32768Hz를 128×256으로 분주한다. RTC가 최초 초기화되는 경우 시험 날짜 2026-11-11 수요일, 시각 12:34:58을 넣는다. 이미 초기화됐으면 기존 값을 이어간다. RTC 시각을 읽은 뒤 날짜 레지스터를 읽어 shadow-register 잠금을 해제한다.

PC 출력은 USART2, PA2=TX/PA3=RX, 9600bps 8N1이다. USART3의 PC10=TX/PC11=RX와 I2C1의 PB8=SCL/PB9=SDA는 템플릿 설정에 있으며 시각 전송·센서 기능은 후속 구현이다. LSE용 PC14/PC15를 다른 기능으로 사용하지 않는다. 외부 RTC 모듈을 추가하는 구성은 아니다.

RTC 설정은 ece2_474_routine.c에서 수행하며 .ioc에는 활성화가 반영돼 있지 않다. RTC HAL 드라이버를 호출하지 않으므로 hrtc와 해당 드라이버 없이 빌드하는 구성이 맞다. CubeMX 재생성 시 수동 RTC 설정과 핀 충돌을 확인한다.

ARM 컴파일은 Clang으로 30개 파일에서 확인했다. 검토 환경의 원래 GCC 실행에는 DLL 오류가 있어 전체 펌웨어 링크·다운로드를 검증하지 못했다. 실제 RTC 진행·LSE 기동·PC 출력과 달력 경계 동작은 보드에서 확인한다.

## tools와 워크스페이스

Vivado에서는 최종 설계에 필요한 회로 파일을 Design Sources, .sv 테스트벤치를 Simulation Sources, XDC를 Constraints에 등록한다. 단독 시험은 stopwatch_top 또는 scheduler_top, 통합 시험은 top을 최상위로 지정한다. 등록할 정확한 소스 목록은 각 폴더의 simulation.json에서 확인한다. 통합 프로젝트에는 system/src/top.v와 stopwatch/src의 공통 모듈 및 stopwatch.v, scheduler/src/scheduler.v를 한 번씩 등록한다.

system/system.code-workspace는 VS Code에서 전체 코드를 보는 작업 화면이다. STM32 기본 워크스페이스 설정을 가져오고 CMake 소스 경로를 MCU 폴더로 지정했다. 자동 CMake 구성은 껐다. 빌드 시 STM32 확장과 필요한 도구를 설치하고 MCU 프로젝트를 선택한다. 폴더를 한 화면에 여는 것 자체가 FPGA 코드를 STM32 빌드에 포함시키지 않는다. STM32 빌드 대상은 main_project의 CMake 소스 목록이다. 내장 ST-Link 디버그 항목의 프로젝트 선택은 실제 VS Code에서 확인한다.

전체 워크스페이스에서 STM32 확장 동작이 불확실하면 mcu/main_project/ece2_474.code-workspace를 별도 창으로 열어 기존 방식으로 빌드·다운로드한다. 설정 파일을 포함한 준비 상태이며, 현재 검토 환경에서 VS Code 확장의 빌드·다운로드를 직접 조작해 확인한 상태는 아니다.

## 다음 확인 순서

1. STM32를 빌드·다운로드하고 PC 출력의 1초 진행을 확인한다.
2. FPGA 입력 클록을 주파수 조절기로 50MHz에 맞추고 스톱워치 단독 동작을 확인한다.
3. 예약 단독 동작에서 5초 대기·10초 ON·취소를 LED로 확인한다.
4. 통합 top으로 화면 전환·독립 진행·공통 취소를 확인한다.
5. 외부 BDIO 레벨·버스 스위치를 확인하고 MOSFET 출력과 MCU UART를 연결한다.

1차 구현 이후 시각 UART·절대시각 예약·INA219 측정·전력/에너지 계산·에너지 한도 차단·통신 오류 처리를 확장한다.


## 2026-11-14 검증 및 후속 확인

- 예약제어: 실제 Vivado 로그 `SCHEDULER PASS checks=160`.
- system: 실제 Vivado 로그 `SYSTEM PASS checks=14`.
- 스톱워치: 기존 검증 로그 `RESULT: PASS (0 errors)`, 현재 RTL과 검증본 일치.
- 세 FPGA 프로젝트 모두 합성·구현·비트스트림 생성 성공. 지정된 50MHz 내부 타이밍 만족.
- MCU 30개 C/어셈블리 파일의 Clang ARM 객체 재컴파일 오류 0개. GCC 전체 링크·다운로드·실물 RTC는 확인 전이다.
- GPIO 커넥터는 빵판 옆 PORT A(I/O 00~07)·PORT B(I/O 08~15). I/O 00=F8, 01=E8, 02=A7이다.
- PI3C3245 BE는 LOW 연결/HIGH 차단이다. 제공 회로도는 DIP 접점 열림→풀다운 LOW→연결 구조이며 실물 SW5 위치를 대조한다.
- 외부 GPIO 경로에는 온보드 100Ω과 PI3C3245가 있다. 외부 Gate 저항 330Ω·풀다운 20kΩ은 별도로 사용한다.
- CFGBVS·CONFIG_VOLTAGE는 미지정 경고가 남아 있다. 실제 구성 뱅크 정보를 확인 후 설정한다. GPIO 3.3V와 구분한다.
- 소스/Git: `<PROJECT_ROOT>`. Vivado 작업·비트스트림: `<VIVADO_ROOT>`.
- 저장소: http<LOCAL_PATH>
- 1차 태그 `v0.1.0`은 실물 검증 전 기준 소스 버전이다.
