# ECE2 프로젝트 — 2차 구현

FPGA: HBE Combo II-DLD S75 / XC7S75FGGA484-1. MCU: NUCLEO-G474RE.
1차 구현은 Git 이력에 보존하고, 현재 소스는 2차 통합 구현을 기준으로 한다.

## 현재 기능

- STM32 RTC 날짜·현재 시각 수신, PC 시각 동기화 도구.
- 스톱워치 시작·일시정지·재개 및 화면별 초기화/예약 취소.
- 상대시간 예약: 기본 5초 대기 후 10초 동작. 실행 중 재시작·일시정지 없음.
- UART T/M/S 프레임, MCU 실행 준비 확인, 계측 이상·통신 타임아웃 시 Gate OFF.
- 7세그먼트와 LCD에 시각·날짜·스톱워치·예약·계측값 표시.
- INA219 계측, 부하 저항값 설정 및 전력·에너지 계산.

## 폴더

| 경로 | 내용 |
|---|---|
| `fpga/system` | 2차 통합 top, XDC, 테스트벤치, Vivado Tcl |
| `fpga/stopwatch` | 스톱워치·표시·공통 구동 모듈 |
| `fpga/scheduler` | 예약제어 FSM |
| `fpga/uart` | UART 송수신·프레임 해석·상태 회신 |
| `fpga/gpio_test` | GPIO 전압 확인용 독립 설계 |
| `mcu/main_project` | STM32 프로젝트 및 PC 시각 동기화 도구 |
| `docs` | 구현·인터페이스 설명 |
| `evidence` | 검증 로그·파형·사진 |

## 확인된 상태

2026-11-16 Vivado system2의 배치·배선 결과: WNS +8.855 ns, TNS 0 ns,
WHS +0.045 ns, THS 0 ns. 50 MHz 조건에서 setup/hold 위반 없음.
비트스트림 생성 성공. 최신 근거는 `evidence/system2/vivado_verified/`에 보존한다.
이전 타이밍 실패 및 자동 실행 환경 오류 로그는 이력이며 최종 빌드 결과와 구분한다.

HDL 정적 분석 오류 0. 날짜 해석 RTL 36,525일 및 잘못된 입력 12건,
MCU RTC 레지스터 해석 73,050건을 검증했다. ARM 객체 30개 컴파일 오류 0.
Icarus는 실행 파일 생성 후 컴파일러 종료 시 예외가 발생한 사례가 있으므로
시뮬레이션 PASS와 컴파일러 종료 상태를 구분한다.

STM32 실제 도구 체인의 전체 링크·다운로드, RTC 실시간 동작,
FPGA·STM32·INA219·외부 부하를 함께 연결한 시연은 후속 실험에서 확인한다.
기존 GPIO 시험에서 HIGH 약 3.3 V / LOW 약 0 V를 확인했으며,
이는 2차 통합 회로의 실물 검증 완료를 뜻하지 않는다.

## 전압 설정

일반 I/O는 기존 실험과 같은 LVCMOS33. CFGBVS/CONFIG_VOLTAGE는 미지정이며
CFGBVS-1 경고가 남는다. 구성 뱅크 실제 전압·핀 연결은 확인되지 않았고,
GPIO 측정이나 경고 제거만으로 해당 연결을 검증할 수 없다.
확인되지 않은 값을 넣어 경고를 제거하지 않았다.

## 기본 연결 및 조작

- PORT A I/O00(F8): 외부 330Ω을 거쳐 MOSFET Gate.
- PORT A I/O01(E8): FPGA RX ← MCU PC10 TX(CN7-1).
- PORT A I/O02(A7): FPGA TX → MCU PC11 RX(CN7-2).
- INA219: VCC=STM 3V3, SCL=PB8(D15), SDA=PB9(D14), 공통 GND.
- SW5 PORT A 접점 OFF가 연결 조건이다. 실제 GPIO 측정으로 통과 여부 확인.
- 버튼 1 전체 리셋, 2 시작/스톱워치 일시정지, 3 현재 화면 초기화·예약 취소,
  4 화면 전환, 5 시각/날짜 또는 V/I/P/E 표시 전환.
- 50Ω 부하를 사용할 때 MCU PC 직렬 모니터에서 `RLOAD,50000` 입력.
  단위는 mΩ이며 재시작 시 기본값 330Ω으로 돌아간다.

외부 5 V는 부하 경로용이며 GPIO·UART에 직접 연결하지 않는다.
외부 전원 OFF 상태에서 다운로드하고 리셋·취소 시 Gate–Source 약 0 V를 확인한다.
전원 인가 전 실제 MOSFET 핀 배치·배선·저항 정격을 확인한다.
50Ω 양단에 5 V가 걸리는 경우 소비전력은 0.5 W이며, 실제 저항 정격은 별도 확인한다.

## Vivado

소스 저장소: `D:/Engineering/Verilog_Lab/project`.
Vivado 생성물: `D:/Engineering/Vivado_Work/project/system2`.
Vivado Tcl Console에서 다음을 실행한다.

```tcl
source D:/Engineering/Verilog_Lab/project/fpga/system/prepare_fixed_project.tcl
```

프로젝트 이름은 `system2`, 설계 top은 `top`, 통합 시뮬레이션 top은 `tb_system`이다.
빌드 검증은 `fpga/system/verify_build.tcl`을 사용하거나 Vivado GUI에서 수행한다.
상세 인터페이스는 `docs/second_implementation_interfaces.md`를 참고한다.
