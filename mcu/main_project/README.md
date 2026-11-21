# STM32G474 펌웨어

- STM32CubeMX 프로젝트 `ece2_474.ioc`의 I²C1 기준 클록은 100 MHz, SCL 목표는 100 kHz다. 빌드에 쓰는 `Core/Src/main.c`의 초기화 값은 `0x40604E73`이다.
- PC USART2는 9600 8N1이며 `TIME`, `GET`, `CLEAR_ENERGY`, `RLOAD`를 지원한다. 저항 명령의 단위는 Ω이다. `RLOAD,100`과 `RLOAD,99.8`을 사용할 수 있다.
- 예약 `WAIT`부터 0.5초 간격으로 결과를 표시한다. 마지막 출력에는 RUN 구간의 마지막 유효 V/I/P, 이번 에너지, 전체 누적이 포함된다.
- VS Code에서 `ece2_474.code-workspace`를 열고 Debug 구성으로 빌드한다. F5로 다운로드하고 `main`에서 정지하면 계속 실행한다.

프로토콜과 실험 전 확인 사항은 [2차 구현 인터페이스](../../docs/second_implementation_interfaces.md)와 [프로젝트 README](../../README.md)를 참조한다.
