# ECE2 프로젝트 — 2차 구현

FPGA: HBE Combo II-DLD S75 / XC7S75FGGA484-1. MCU: NUCLEO-G474RE.
1차 구현은 Git 이력에 보존하고, 현재 소스는 2차 통합 구현을 기준으로 한다.

## 현재 기능

- STM32 RTC 날짜·현재 시각 수신, PC 시각 동기화 도구.
- 스톱워치 시작·일시정지·재개 및 화면별 초기화/예약 취소.
- 상대시간 예약: 기본 5초 대기 후 10초 동작. 실행 중 재시작·일시정지 없음.
- UART T/M/F/S 프레임, MCU 실행 준비 확인, 계측 이상·통신 타임아웃 시 Gate OFF.
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
| [`evidence/system1`](evidence/system1) | 1차 구현 보드 사진·MCU 시각 화면 |
| [`evidence/system2`](evidence/system2) | 2차 회로 사진·GPIO 전압 측정·시뮬레이션 파형 |

## 예약 측정 결과

- PC는 `WAIT`부터 0.5초마다 시각, 상태, V·I·P·이번 에너지·누적 에너지를 출력한다. `DONE` 또는 중단 시 같은 형식으로 마지막 결과를 출력한다.
- 이번 에너지는 Gate ON 구간의 유효 표본으로 계산한다. MCU는 UART 전송 시간을 보정하며 FPGA–MCU 상태 전달과 센서 변환에 따른 경계 오차가 남는다.
- FPGA의 LCD와 7세그먼트는 V·I·P·이번 E를 표시한다. 종료 후 현재 예약의 최종 프레임을 받으면 결과를 고정한다.
- FPGA 표시에 `V`, `mA`, `mW`, `mWh`를 사용한다. PC 전체 누적은 STM32 RAM에 보관한다.

## 부하 전원 인가 전 확인

1. 외부 5 V를 분리하고 공통 GND, INA219 `VCC=3V3`, `VIN+`/`VIN−` 방향과 배선을 확인한다.
2. 모듈의 전원과 배선을 빼고 `VCC–SCL`, `VCC–SDA` 저항을 각각 확인한다. 온보드 풀업이 확인되면 그 저항을 사용한다.
3. 새 펌웨어로 통신할 때 오실로스코프로 `PB8/SCL`의 연속한 상승 에지 사이가 약 10 µs인지 확인한다.
4. 부하가 꺼진 상태에서 Gate–Source 전압이 0 V 근처인지 확인하고, INA219의 무부하 `current_uA`를 음수 유효성 검사 직전에 여러 번 기록한다. 영점 보정값은 실측 후 정한다.
5. 부하 저항 정격과 전원 전류 제한을 확인한 뒤 부하 전원을 인가한다.

## 2차 최종 기준본 검증

- 2026-11-23 14:22:13(KST)에 Vivado 2026.1에서 50 MHz 설계의 `system2` 비트스트림(`top.bit`)을 생성했다. 해당 빌드의 배치·배선 결과는 WNS +6.497 ns, WHS +0.051 ns이며 setup·hold 실패는 각각 0이다. `CFGBVS-1` 경고는 남아 있다.
- `v0.2.2`와 동일한 RTL 및 테스트벤치로 Icarus 시뮬레이션을 실행했다. 최종 변경과 관련된 세 테스트의 결과는 아래와 같다. 생성된 시뮬레이션 실행 파일은 모두 종료 코드 0을 반환했다. Windows에서 Icarus 컴파일러는 실행 파일 생성 뒤 비정상 종료 코드를 반환했다.
- STM32 실험용 ELF에는 INA219 전류 오프셋 −400 µA와 영점 허용 폭 ±300 µA를 적용했다. 실물 통합 시험에서 SCL 약 96.7 kHz, 5 V 미인가 상태의 Gate 동작, 330 Ω·100 Ω·50 Ω 부하의 예약과 계측을 확인했다. 사진과 측정 화면은 [실험 증빙](evidence/system2/photo)에 있다.

| 테스트벤치 | 실행 결과 |
| --- | --- |
| `tb_system` | `INTEGRATED SYSTEM PASS checks=16` |
| `tb_reservation_control` | `RESERVATION CONTROL PASS checks=5306 status_frames=89` |
| `tb_project_lcd` | `LCD PASS: 28 text cases, 75 bus bytes, initialization/timing/snapshot/refresh` |

## 이전 Vivado 빌드 기록

2026-11-16 Vivado system2의 배치·배선 결과: WNS +8.855 ns, TNS 0 ns,
WHS +0.045 ns, THS 0 ns. 50 MHz 조건에서 setup/hold 위반 없음.
비트스트림을 생성했다. 원본 Vivado 로그와 리포트는 로컬에서 관리한다.
이전 타이밍 실패 및 자동 실행 환경 오류 로그는 이력이며 최종 빌드 결과와 구분한다.

HDL 정적 분석 오류 0. 날짜 해석 RTL 36,525일 및 잘못된 입력 12건,
MCU RTC 레지스터 해석 73,050건을 검증했다. ARM 객체 30개 컴파일 오류 0.
Icarus는 실행 파일 생성 후 컴파일러 종료 시 예외가 발생한 사례가 있으므로
시뮬레이션 PASS와 컴파일러 종료 상태를 구분한다.

당시에는 GPIO 단독 시험에서 HIGH 약 3.3 V / LOW 약 0 V를 확인했다.
STM32·FPGA·INA219·외부 부하의 실물 통합 시험은 2026-11-23에 진행했다.

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
- 저항을 교체하고 부하 OFF 상태에서 PC 시리얼에 `RLOAD,50` 또는 `RLOAD,99.8`을 입력한다.
  입력 단위는 Ω이고 MCU 리셋 시 기본값은 330 Ω이다.

외부 5 V는 부하 경로용이며 GPIO·UART에 직접 연결하지 않는다.
외부 전원 OFF 상태에서 다운로드하고 리셋·취소 시 Gate–Source 약 0 V를 확인한다.
전원 인가 전 실제 MOSFET 핀 배치·배선·저항 정격을 확인한다.
50Ω 양단에 5 V가 걸리는 경우 소비전력은 0.5 W이며, 실제 저항 정격은 별도 확인한다.
