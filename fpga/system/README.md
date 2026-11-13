# FPGA 1차 통합

system.code-workspace를 열면 MCU·스톱워치·예약 제어·통합 코드·증빙을 함께 볼 수 있다.

`src/top.v`가 기존 스톱워치와 상대시간 예약 제어를 연결한다. 공통 회로는 기존 stopwatch/src의 한 벌을 참조한다. 각 단독 시험 폴더는 자체 소스와 테스트벤치를 유지한다. system/src에 동일 모듈을 다시 복사하지 않는다.

버튼 1(K4)은 전체 리셋, 버튼 2(N8)는 현재 모드 시작/일시정지 또는 예약 시작, 버튼 3(N4)은 예약 취소 및 스톱워치 초기화다. 버튼 4(N1)는 화면 모드를 전환한다. 처음 모드는 스톱워치다. 모드 전환 중에도 실행 중인 기능은 계속 동작한다. 버튼 3은 모든 모드에서 예약을 취소한다. LED8(N5)은 예약 load_en만 표시한다.

예약은 5초 대기 후 10초 ON이다. 예약 화면 왼쪽은 상태 0=IDLE/1=WAIT/2=RUN/3=DONE, 오른쪽은 남은 MM.SS이다. 시계 UART와 실제 MOSFET 외부 핀은 후속 연결 단계다. 현재 LED로 출력 상태를 확인한다.

보드 클록 F(50MHz), 키패드 선택은 버튼 모드로 설정한다. 핀 배치는 스톱워치 XDC를 유지하고 버튼4를 추가했다. 실제 보드 검증 전이다.

워크스페이스는 전체 코드 탐색·편집에 사용한다. 시뮬레이션과 합성은 Vivado에서 수행한다. simulation.json의 sources 목록에 있는 회로 파일을 Design Sources, sim/tb_system.sv를 Simulation Sources, constraints/pins.xdc를 Constraints에 등록한다.
최상위 모듈은 top, 시뮬레이션 최상위는 tb_system이다. Run Behavioral Simulation으로 시뮬레이션을 실행한다.
