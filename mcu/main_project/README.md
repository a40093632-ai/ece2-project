# STM32G474 펌웨어

- STM32CubeMX 프로젝트 `ece2_474.ioc`의 I²C1 기준 클록은 100 MHz, SCL 목표는 100 kHz다. 빌드에 쓰는 `Core/Src/main.c`의 초기화 값은 `0x40604E73`이다.
- PC USART2는 9600 8N1이며 `TIME`, `GET`, `CLEAR_ENERGY`, `RLOAD`를 지원한다. 저항 명령의 단위는 Ω이다. `RLOAD,100`과 `RLOAD,99.8`을 사용할 수 있다.
- 예약 `WAIT`부터 0.5초 간격으로 결과를 표시한다. 마지막 출력에는 RUN 구간의 마지막 유효 V/I/P, 이번 에너지, 전체 누적이 포함된다.
- VS Code에서 `ece2_474.code-workspace`를 열고 Debug 구성으로 빌드한다. F5로 다운로드하고 `main`에서 정지하면 계속 실행한다.

프로토콜과 실험 전 확인 사항은 [2차 구현 인터페이스](../../docs/second_implementation_interfaces.md)와 [프로젝트 README](../../README.md)를 참조한다.

## INA219 영점 진단

PC 시리얼 모니터에서 `SENSOR?`와 줄바꿈을 보내면 한 줄만 응답한다. `last_shunt`는 마지막으로 읽은 부호 있는 션트 레지스터 값, `raw_uA`는 보정 전 전류, `age_ms`는 그 판독 후 경과 시간이다. `valid`와 `reason`은 현재 계측 상태다. 최초 판독 전에는 `no_sample`이 표시된다. 통신 오류 시 마지막 원시값이 남을 수 있으므로 age와 reason을 함께 읽는다.

외부 부하 전원을 끄고 영점 분포를 기록한다. 필요할 때만 ece2_474_routine.c의 CURRENT_OFFSET_UA(부호 있는 영점 중심)와 CURRENT_ZERO_BAND_UA(중심 제거 후 허용 폭)를 정하고 다시 빌드한다. 두 기본값은 0 µA다. 모듈과 션트가 같으면 매 기동 시 값을 입력할 필요가 없다. 5 V 인가 후 Gate OFF 전류는 별도로 확인한다. 범위 밖 음수·I²C 오류는 계속 무효로 처리한다.
