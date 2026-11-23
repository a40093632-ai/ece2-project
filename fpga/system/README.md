# FPGA 2차 통합 시스템

FPGA는 시계, 스톱워치, 예약 출력과 측정 표시를 담당한다. STM32가 RTC 시각과 INA219 계측값을 전송하고, FPGA가 예약 상태와 Gate 명령을 회신한다. 기본 화면은 시계다.

| 버튼 | 동작 |
|---|---|
| 1 (K4) | 전체 리셋, Gate OFF |
| 2 (N8) | 예약 화면에서 시작, 스톱워치 화면에서 시작·일시정지·재개 |
| 3 (N4) | 예약 화면에서 취소 또는 오류 확인, 스톱워치 화면에서 초기화 |
| 4 (N1) | 시계 → 스톱워치 → 예약 → 측정 |
| 5 (P6) | 시계의 날짜·시각 또는 측정 화면 V/I/P/E 선택 |

예약은 4 ARM(실행 ID 승인) → 1 WAIT(5초) → 2 RUN(10초) → 3 DONE 순으로 진행한다. 0은 IDLE, 5는 FAULT다. 화면 전환 중에도 예약과 스톱워치는 진행한다. LED5~8은 각각 ARM·WAIT, RUN, FAULT, Gate 명령을 나타낸다.

첫 IDLE과 ARM·WAIT에서 V/I/P는 새 유효 계측에 따라 갱신하고 이번 E는 0이다. RUN에서는 같은 실행 ID의 표본을 사용한다. 종료 후 결과는 같은 ID의 F로 확정하며 다음 실행까지 유지한다. RUN 진입 전 취소·오류, 부분 결과, F 미수신은 측정 LCD에서 구분한다. FPGA는 이번 E, PC는 이번 E와 누적 Total을 표시한다.

MAIN_CLOCK1(B6)은 50 MHz다. PORT A I/O00(F8)은 Gate, I/O01(E8)은 FPGA RX, I/O02(A7)는 FPGA TX다. 제약 파일은 constraints/pins.xdc다.

Vivado Tcl Console에서 저장소 루트로 이동한 뒤 다음 두 줄을 실행한다.

```tcl
source {fpga/system/prepare_fixed_project.tcl}
source {fpga/system/verify_build.tcl}
```

프로젝트 이름은 system2, 최상위 모듈은 top이다. tb_system은 전체 top의 기본 조작, tb_reservation_control은 UART 선로와 예약·오류·최종 결과, tb_project_lcd는 LCD 문자열과 버스 출력을 검증한다. 시뮬레이션에서는 해당 모듈을 sim_1의 top으로 지정하고 run all을 실행한다.
