/*
 * STM32G474RE - 스마트 전력관리 프로젝트 2차 담당 코드
 *
 * 구현 범위
 *  - LSE / RTC prescaler / calendar clock setup and PC date-time setting
 *  - PC(USART2): TIME / GET / RLOAD / CLEAR_ENERGY 명령, CSV 출력
 *  - INA219(I2C1): shunt/bus raw register 읽기
 *  - I = Vshunt / Rshunt, Pload = I^2 * Rload 계산
 *  - Etotal / Esession 누적 (HAL_GetTick 기반, trapezoidal integration)
 *  - FPGA(USART3): T/M 프레임 송신, S 프레임 수신
 *
 * 프로젝트 전제(프로젝트 파일에서 확인 필요)
 *  - STM32G474RE, HAL 사용
 *  - PB8/PB9 = I2C1 SCL/SDA, peripheral handle = hi2c1
 *  - USART2 = PC ST-LINK VCP, USART3 = FPGA link
 *  - USART2/USART3: 9600 baud, 8 data bits, no parity, 1 stop bit
 *  - 이 파일에서 LSE / RTC clock source 및 1 Hz prescaler도 초기화
 *  - main.c에서 hi2c1, huart2, huart3가 정의되고 ece2_474.h에서 extern 선언됨
 *
 * 주의
 *  - 이 코드는 가이드의 센서/통신 단위를 고정한 기준 구현입니다.
 *  - FPGA 담당자와 아래 $T/$M/$S 프레임 형식을 반드시 동일하게 맞춰야 합니다.
 *  - RSHUNT_MOHM은 INA219 모듈의 실측 션트값으로, RLOAD_MOHM은 부하 저항 실측값으로 수정하세요.
 *  - FPGA 담당자는 파일 하단의 고정 프레임 규약을 그대로 사용하거나 양쪽 코드를 함께 수정해야 합니다.
 */

#include "ece2_474.h"
#include "main.h"

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <limits.h>

/* -------------------------------------------------------------------------- */
/* 사용자 설정                                                                 */
/* -------------------------------------------------------------------------- */

#ifndef ECE2_I2C_HANDLE
#define ECE2_I2C_HANDLE       hi2c1
#endif

#ifndef ECE2_PC_UART_HANDLE
#define ECE2_PC_UART_HANDLE   huart2
#endif

#ifndef ECE2_FPGA_UART_HANDLE
#define ECE2_FPGA_UART_HANDLE huart3
#endif

#define INA219_ADDR_7BIT       0x40U   /* A0=A1=GND일 때 기본 후보 */
#define INA219_ADDR_HAL        (INA219_ADDR_7BIT << 1U)
#define INA219_REG_CONFIG      0x00U
#define INA219_REG_SHUNT       0x01U
#define INA219_REG_BUS         0x02U

/* BRNG=32V, PGA=±320mV, BADC=12bit, SADC=12bit, triggered shunt+bus mode */
#define INA219_CONFIG_TRIGGER  0x399BU
#define INA219_BUS_CNVR        0x0002U

#define RSHUNT_MOHM            100U     /* R100 표기: 명목 0.1Ω = 100mΩ */
#define DEFAULT_RLOAD_MOHM     330000U  /* 기본값 330Ω. 반드시 실제 측정값으로 변경 */

/* Signed zero-current reading, in uA. Fill in only after measuring this module. */
#define CURRENT_OFFSET_UA      0
#define CURRENT_ZERO_BAND_UA   0  /* symmetric residual noise after offset correction */
#define SENSOR_PERIOD_MS       100U
#define SENSOR_CONVERT_WAIT_MS 2U
#define SENSOR_TIMEOUT_MS      25U
#define SENSOR_RETRY_MS        1000U
#define FPGA_MEAS_PERIOD_MS    200U
#define FPGA_TIME_PERIOD_MS    1000U
#define PC_LOG_PERIOD_MS       500U
#define MAX_INTEGRATE_GAP_MS   250U
/* $S carries 28 bytes at 9600 baud, with ten wire bits per byte. */
#define FPGA_STATUS_WIRE_MS   29U

#define RX_RING_SIZE           256U    /* power of 2 */
#define RX_RING_MASK            (RX_RING_SIZE - 1U)
#define TX_RING_SIZE           1024U   /* power of 2 */
#define TX_RING_MASK            (TX_RING_SIZE - 1U)
#define PC_LINE_SIZE            128U
#define FPGA_LINE_SIZE          160U

#define RTC_INIT_TIMEOUT_MS     100U
#define RTC_LSE_TIMEOUT_MS      5000U
#define RTC_SYNC_TIMEOUT_MS     200U

/* STM32G4 RCC_BDCR / PWR_CR1 bit masks (RM0440). */
#define ECE2_BDCR_LSEON         (1U << 0U)
#define ECE2_BDCR_LSERDY        (1U << 1U)
#define ECE2_BDCR_RTCSEL_MASK   (3U << 8U)
#define ECE2_BDCR_RTCSEL_LSE    (1U << 8U)
#define ECE2_BDCR_RTCEN         (1U << 15U)
#define ECE2_PWR_CR1_DBP        (1U << 8U)
#define RTC_VALID_MAGIC         0x52544331U /* "RTC1": PC에서 시각 설정 완료 표시 */

#ifndef RTC_ICSR_RSF
#define RTC_ICSR_RSF            (1U << 5U)
#endif
#ifndef RTC_ICSR_INITS
#define RTC_ICSR_INITS          (1U << 4U)
#endif

/* -------------------------------------------------------------------------- */
/* UART RX/TX queues                                                           */
/* -------------------------------------------------------------------------- */

typedef struct
{
    volatile uint16_t head;
    volatile uint16_t tail;
    volatile uint32_t dropped;
    uint8_t data[RX_RING_SIZE];
} ByteRing_t;

typedef struct
{
    volatile uint32_t head;
    volatile uint32_t tail;
    volatile uint16_t active_chunk;
    volatile uint8_t busy;
    volatile uint32_t dropped;
    uint8_t data[TX_RING_SIZE];
} TxRing_t;

static ByteRing_t pc_rx_ring;
static ByteRing_t fpga_rx_ring;
static TxRing_t pc_tx_ring;
static TxRing_t fpga_tx_ring;

static uint8_t uart2_rx_ece2;
static uint8_t uart3_rx_ece2;

static char pc_line[PC_LINE_SIZE];
static uint16_t pc_line_len;
static bool pc_line_discard;
static char fpga_line[FPGA_LINE_SIZE];
static uint16_t fpga_line_len;

/* -------------------------------------------------------------------------- */
/* 상태 데이터                                                                */
/* -------------------------------------------------------------------------- */

typedef struct
{
    uint32_t vbus_mV;
    int32_t current_uA;
    uint64_t power_uW;
    uint32_t sample_tick_ms;
    uint8_t valid;
} Measurement_t;

static Measurement_t g_measurement;

static uint8_t g_rtc_valid;
static uint8_t g_rtc_clock_ready;
static uint8_t g_ina219_ready;
static uint8_t g_sensor_conversion_pending;
static uint32_t g_sensor_trigger_tick;
static uint32_t g_sensor_last_retry_tick;
static uint32_t g_sensor_generation;
static uint32_t g_last_m_generation;

static uint32_t g_fpga_tx_seq;
static uint32_t g_fpga_measure_seq;
static uint16_t g_run_id;
static uint8_t g_session_ack, g_arm_phase, g_have_s;
static uint16_t g_last_s_seq;
static uint32_t g_last_s_tick;

static uint32_t g_rload_mohm = DEFAULT_RLOAD_MOHM;

static uint64_t g_etotal_2nJ;
static uint64_t g_esession_2nJ;
static bool g_session_active;
static bool g_session_running;
static bool g_session_partial;
static bool g_session_final;
static bool g_integrate_previous;
static uint32_t g_run_start_tick;
static Measurement_t g_run_sample;
static Measurement_t g_pending_sample;
static bool g_pc_report_active;
static bool g_pc_final_pending;

static uint8_t g_fpga_state_known;
static uint8_t g_fpga_gate_cmd;
static uint8_t g_fpga_state_number;
static char g_fpga_state[8] = "UNKNOWN";
static char g_fpga_reason[16] = "UNKNOWN";

static uint32_t g_next_sensor_tick;
static uint32_t g_next_fpga_meas_tick;
static uint32_t g_next_fpga_time_tick;
static uint32_t g_next_pc_log_tick;

/* -------------------------------------------------------------------------- */
/* 작은 공통 함수                                                             */
/* -------------------------------------------------------------------------- */

static bool TickDue(uint32_t now, uint32_t deadline)
{
    return ((int32_t)(now - deadline) >= 0);
}

static uint8_t BinToBcd(uint8_t value)
{
    return (uint8_t)(((value / 10U) << 4U) | (value % 10U));
}

static bool IsLeapYear(uint16_t year)
{
    return ((year % 4U) == 0U);
}

static uint8_t DaysInMonth(uint16_t year, uint8_t month)
{
    static const uint8_t days[12] =
    {
        31U, 28U, 31U, 30U, 31U, 30U,
        31U, 31U, 30U, 31U, 30U, 31U
    };

    if ((month == 0U) || (month > 12U))
    {
        return 0U;
    }

    if ((month == 2U) && IsLeapYear(year))
    {
        return 29U;
    }

    return days[month - 1U];
}

/* STM32 RTC WDU: Monday=1 ... Sunday=7 */
static uint8_t CalculateWeekday(uint16_t year, uint8_t month, uint8_t day)
{
    int y = (int)year;
    int m = (int)month;
    int h;

    if (m < 3)
    {
        m += 12;
        y -= 1;
    }

    h = ((int)day + (13 * (m + 1)) / 5 + (y % 100) + ((y % 100) / 4)
         + ((y / 100) / 4) + 5 * (y / 100)) % 7;

    /* Zeller: 0=Saturday, 1=Sunday, 2=Monday ... */
    return (uint8_t)(((h + 5) % 7) + 1);
}

static bool DateTimeIsValid(uint16_t year, uint8_t month, uint8_t day,
                            uint8_t hour, uint8_t minute, uint8_t second)
{
    if ((year < 2000U) || (year > 2099U)) return false;
    if ((month < 1U) || (month > 12U)) return false;
    if ((day < 1U) || (day > DaysInMonth(year, month))) return false;
    if (hour > 23U) return false;
    if (minute > 59U) return false;
    if (second > 59U) return false;
    return true;
}

/* -------------------------------------------------------------------------- */
/* RTC: LSE clock / prescaler / calendar                                       */
/* -------------------------------------------------------------------------- */

typedef struct
{
    uint16_t year;
    uint8_t month;
    uint8_t day;
    uint8_t weekday;
    uint8_t hour;
    uint8_t minute;
    uint8_t second;
} DateTime_t;

static bool RTC_WaitForInitFlag(uint32_t timeout_ms)
{
    uint32_t start = HAL_GetTick();
    while ((READ_BIT(RTC->ICSR, RTC_ICSR_INITF) == 0U))
    {
        if ((uint32_t)(HAL_GetTick() - start) >= timeout_ms)
        {
            return false;
        }
    }
    return true;
}

static bool RTC_WaitForSync(void)
{
    uint32_t start;

    /* Shadow registers are refreshed after RSF is cleared. */
    RTC->WPR = 0xCAU; RTC->WPR = 0x53U;
    CLEAR_BIT(RTC->ICSR, RTC_ICSR_RSF);
    start = HAL_GetTick();
    while (READ_BIT(RTC->ICSR, RTC_ICSR_RSF) == 0U)
    {
        if ((uint32_t)(HAL_GetTick() - start) >= RTC_SYNC_TIMEOUT_MS)
        {
            RTC->WPR = 0xFFU;
            return false;
        }
    }
    RTC->WPR = 0xFFU;
    return true;
}

static bool RTC_ClockInit(void)
{
    uint32_t start;
    uint32_t rtc_source;

    /* Enable access to the backup domain without resetting it. */
    __HAL_RCC_PWR_CLK_ENABLE();
    HAL_PWR_EnableBkUpAccess();
    __HAL_RCC_RTCAPB_CLK_ENABLE();

    rtc_source = READ_BIT(RCC->BDCR, ECE2_BDCR_RTCSEL_MASK);
    if ((rtc_source != 0U) && (rtc_source != ECE2_BDCR_RTCSEL_LSE))
    {
        /* Migrate an earlier lab's RTC source. The old calendar is invalidated;
           the PC must supply actual time again after the backup reset. */
        __HAL_RCC_BACKUPRESET_FORCE();
        __HAL_RCC_BACKUPRESET_RELEASE();
        rtc_source = 0U;
    }
    if (rtc_source == 0U)
    {
        /* First setup: use the board's 32.768 kHz LSE crystal. */
        SET_BIT(RCC->BDCR, ECE2_BDCR_LSEON);
        start = HAL_GetTick();
        while (READ_BIT(RCC->BDCR, ECE2_BDCR_LSERDY) == 0U)
        {
            if ((uint32_t)(HAL_GetTick() - start) >= RTC_LSE_TIMEOUT_MS)
            {
                return false;
            }
        }

        MODIFY_REG(RCC->BDCR, ECE2_BDCR_RTCSEL_MASK, ECE2_BDCR_RTCSEL_LSE);
    }
    else if (rtc_source != ECE2_BDCR_RTCSEL_LSE)
    {
        /* Do not silently reset or replace a backup-domain clock source. */
        return false;
    }

    /* A previously selected LSE may have been stopped by a power event. */
    SET_BIT(RCC->BDCR, ECE2_BDCR_LSEON);
    start = HAL_GetTick();
    while (READ_BIT(RCC->BDCR, ECE2_BDCR_LSERDY) == 0U)
    {
        if ((uint32_t)(HAL_GetTick() - start) >= RTC_LSE_TIMEOUT_MS)
        {
            return false;
        }
    }
    SET_BIT(RCC->BDCR, ECE2_BDCR_RTCEN);

    /* Configure prescalers only if the calendar has never been initialized.
       32768 Hz / (127 + 1) / (255 + 1) = 1 Hz. */
    if ((READ_BIT(RTC->ICSR, RTC_ICSR_INITS) == 0U) ||
        ((RTC->PRER & 0x007F7FFFU) != ((127U << 16U) | 255U)) ||
        ((RTC->CR & (RTC_CR_FMT | RTC_CR_BYPSHAD)) != 0U))
    {
        TAMP->BKP0R = 0U; /* Configuration repair requires PC synchronization. */
        RTC->WPR = 0xCAU;
        RTC->WPR = 0x53U;
        SET_BIT(RTC->ICSR, RTC_ICSR_INIT);
        if (!RTC_WaitForInitFlag(RTC_INIT_TIMEOUT_MS))
        {
            CLEAR_BIT(RTC->ICSR, RTC_ICSR_INIT);
            RTC->WPR = 0xFFU;
            return false;
        }

        CLEAR_BIT(RTC->CR, RTC_CR_FMT | RTC_CR_BYPSHAD); /* 24-hour, coherent shadows */
        /* RM0440: PRER는 두 번의 별도 write access로 설정해야 합니다.
           먼저 PREDIV_S, 다음 PREDIV_A와 PREDIV_S 전체 값을 기록합니다. */
        RTC->PRER = 255U;
        RTC->PRER = (127U << 16U) | 255U;
        CLEAR_BIT(RTC->ICSR, RTC_ICSR_INIT);
        RTC->WPR = 0xFFU;
    }

    if (!RTC_WaitForSync())
    {
        return false;
    }

    g_rtc_clock_ready = 1U;
    return true;
}

static bool RTC_ReadDateTime(DateTime_t *dt)
{
    uint32_t tr;
    uint32_t dr;
    uint8_t hour;
    uint8_t minute;
    uint8_t second;
    uint8_t year2;
    uint8_t month;
    uint8_t day;

    if ((dt == NULL) || (g_rtc_clock_ready == 0U) ||
        (TAMP->BKP0R != RTC_VALID_MAGIC))
    {
        /* 공장 초기화된 2000-01-01 등의 값을 실제 시각으로 오인하지 않습니다. */
        return false;
    }

    /* STM32G4 RTC shadow register read order: TR first, then DR. */
    tr = RTC->TR;
    dr = RTC->DR;

    second = (uint8_t)((((tr >> 4U) & 0x07U) * 10U) + (tr & 0x0FU));
    minute = (uint8_t)((((tr >> 12U) & 0x07U) * 10U) + ((tr >> 8U) & 0x0FU));
    hour   = (uint8_t)((((tr >> 20U) & 0x03U) * 10U) + ((tr >> 16U) & 0x0FU));

    year2 = (uint8_t)((((dr >> 20U) & 0x0FU) * 10U) + ((dr >> 16U) & 0x0FU));
    month = (uint8_t)((((dr >> 12U) & 0x01U) * 10U) + ((dr >> 8U) & 0x0FU));
    day   = (uint8_t)((((dr >> 4U) & 0x03U) * 10U) + (dr & 0x0FU));

    dt->year = (uint16_t)(2000U + year2);
    dt->month = month;
    dt->day = day;
    dt->weekday = (uint8_t)((dr >> 13U) & 0x07U);
    dt->hour = hour;
    dt->minute = minute;
    dt->second = second;

    return DateTimeIsValid(dt->year, dt->month, dt->day,
                           dt->hour, dt->minute, dt->second) &&
           dt->weekday == CalculateWeekday(dt->year, dt->month, dt->day);
}

static bool RTC_SetDateTime(uint16_t year, uint8_t month, uint8_t day,
                            uint8_t hour, uint8_t minute, uint8_t second)
{
    uint8_t weekday;

    if ((g_rtc_clock_ready == 0U) ||
        !DateTimeIsValid(year, month, day, hour, minute, second))
    {
        return false;
    }

    weekday = CalculateWeekday(year, month, day);

    /* 시각 갱신 도중 실패하면 기존 시각을 유효하다고 보고하지 않습니다. */
    TAMP->BKP0R = 0U;

    /* Unlock RTC write protection. */
    RTC->WPR = 0xCAU;
    RTC->WPR = 0x53U;

    /* Enter initialization mode. */
    SET_BIT(RTC->ICSR, RTC_ICSR_INIT);
    if (!RTC_WaitForInitFlag(RTC_INIT_TIMEOUT_MS))
    {
        CLEAR_BIT(RTC->ICSR, RTC_ICSR_INIT);
        RTC->WPR = 0xFFU;
        return false;
    }

    /* 24-hour mode. The existing RTC prescaler/source is not modified here. */
    CLEAR_BIT(RTC->CR, RTC_CR_FMT);

    RTC->TR = ((uint32_t)BinToBcd(hour) << 16U)
            | ((uint32_t)BinToBcd(minute) << 8U)
            | (uint32_t)BinToBcd(second);

    RTC->DR = ((uint32_t)BinToBcd((uint8_t)(year % 100U)) << 16U)
            | ((uint32_t)weekday << 13U)
            | ((uint32_t)BinToBcd(month) << 8U)
            | (uint32_t)BinToBcd(day);

    /* Exit initialization mode and lock writes again. */
    CLEAR_BIT(RTC->ICSR, RTC_ICSR_INIT);
    RTC->WPR = 0xFFU;

    if (!RTC_WaitForSync())
    {
        return false;
    }

    /* 시스템 리셋 후에도 PC 동기화 완료 여부를 구분합니다. */
    TAMP->BKP0R = RTC_VALID_MAGIC;
    return true;
}

/* -------------------------------------------------------------------------- */
/* INA219 I2C driver                                                           */
/* -------------------------------------------------------------------------- */

static HAL_StatusTypeDef INA219_WriteRegister(uint8_t reg, uint16_t value)
{
    uint8_t tx[2];
    tx[0] = (uint8_t)(value >> 8U);
    tx[1] = (uint8_t)(value & 0xFFU);

    return HAL_I2C_Mem_Write(&ECE2_I2C_HANDLE, INA219_ADDR_HAL, reg,
                             I2C_MEMADD_SIZE_8BIT, tx, 2U, 20U);
}

static HAL_StatusTypeDef INA219_ReadRegister(uint8_t reg, uint16_t *value)
{
    uint8_t rx[2];
    HAL_StatusTypeDef status;

    if (value == NULL)
    {
        return HAL_ERROR;
    }

    status = HAL_I2C_Mem_Read(&ECE2_I2C_HANDLE, INA219_ADDR_HAL, reg,
                              I2C_MEMADD_SIZE_8BIT, rx, 2U, 20U);
    if (status != HAL_OK)
    {
        return status;
    }

    *value = (uint16_t)(((uint16_t)rx[0] << 8U) | (uint16_t)rx[1]);
    return HAL_OK;
}

static bool INA219_Init(void)
{
    if (HAL_I2C_IsDeviceReady(&ECE2_I2C_HANDLE, INA219_ADDR_HAL, 3U, 50U) != HAL_OK)
    {
        g_ina219_ready = 0U;
        return false;
    }

    if (INA219_WriteRegister(INA219_REG_CONFIG, INA219_CONFIG_TRIGGER) != HAL_OK)
    {
        g_ina219_ready = 0U;
        return false;
    }

    g_ina219_ready = 1U;
    g_sensor_conversion_pending = 0U;
    return true;
}

static const char *sensor_reason = "NO_SAMPLE";
static bool have_raw_sample;
static int16_t last_shunt_raw;
static int32_t last_raw_uA;
static uint32_t last_raw_tick;

static void Measurement_SetInvalid(const char *reason)
{
    sensor_reason = reason;
    g_measurement.valid = 0U;
    g_sensor_conversion_pending = 0U;
    if (g_session_running) g_session_partial = true;
    g_pending_sample.valid = 0U;
    g_integrate_previous = false;
    g_sensor_generation++;
}

static void Energy_Add(uint64_t power_sum_uW, uint32_t dt_ms)
{
    /* Trapezoidal integration in half-nJ units. */
    uint64_t delta = power_sum_uW * dt_ms;
    g_esession_2nJ += delta;
    g_etotal_2nJ += delta;
}

static void Energy_CommitSample(const Measurement_t *sample)
{
    uint32_t tick = sample->sample_tick_ms;
    if (g_integrate_previous)
    {
        uint32_t dt = tick - g_run_sample.sample_tick_ms;
        if (dt <= MAX_INTEGRATE_GAP_MS)
            Energy_Add(g_run_sample.power_uW + sample->power_uW, dt);
        else g_session_partial = true;
    }
    else if (!g_run_sample.valid && !g_session_partial)
    {
        uint32_t dt = tick - g_run_start_tick;
        if (dt <= MAX_INTEGRATE_GAP_MS) Energy_Add(2ULL * sample->power_uW, dt);
        else g_session_partial = true;
    }
    g_run_sample = *sample;
    g_integrate_previous = true;
}

static void Energy_IntegrateSample(const Measurement_t *sample)
{
    if (!g_session_running || (int32_t)(sample->sample_tick_ms - g_run_start_tick) < 0) return;
    // Keep one sample pending for the UART notification of Gate OFF.
    if (g_pending_sample.valid) Energy_CommitSample(&g_pending_sample);
    g_pending_sample = *sample;
}

static void Session_Finish(uint32_t tick, bool normal)
{
    if (g_pending_sample.valid && (int32_t)(tick - g_pending_sample.sample_tick_ms) >= 0)
        Energy_CommitSample(&g_pending_sample);
    g_pending_sample.valid = 0U;
    if (g_integrate_previous)
    {
        uint32_t dt = tick - g_run_sample.sample_tick_ms;
        if (dt <= MAX_INTEGRATE_GAP_MS) Energy_Add(2ULL * g_run_sample.power_uW, dt);
        else g_session_partial = true;
    }
    g_session_partial |= !normal || !g_run_sample.valid;
    g_session_active = false;
    g_session_running = false;
    g_integrate_previous = false;
    g_session_final = true;
    g_pc_final_pending = true;
    g_session_ack = 0U;
}

static void INA219_StartConversion(uint32_t now)
{
    if (INA219_WriteRegister(INA219_REG_CONFIG, INA219_CONFIG_TRIGGER) != HAL_OK)
    {
        g_ina219_ready = 0U;
        Measurement_SetInvalid("I2C_TRIGGER");
        return;
    }

    g_sensor_conversion_pending = 1U;
    g_sensor_trigger_tick = now;
}

static void INA219_FinishConversion(uint32_t now)
{
    uint16_t bus_raw;
    uint16_t shunt_raw_u;
    int16_t shunt_raw;
    int64_t shunt_uV;
    int64_t current_uA;
    uint64_t abs_current_uA;
    uint64_t current_sq;
    uint64_t power_uW;
    HAL_StatusTypeDef status;

    status = INA219_ReadRegister(INA219_REG_BUS, &bus_raw);
    if (status != HAL_OK)
    {
        g_ina219_ready = 0U;
        Measurement_SetInvalid("I2C_BUS");
        return;
    }

    /* CNVR=bit1: 새 변환 완료, OVF=bit0: 변환 오버플로 */
    if ((bus_raw & INA219_BUS_CNVR) == 0U)
    {
        if ((uint32_t)(now - g_sensor_trigger_tick) > SENSOR_TIMEOUT_MS)
        {
            g_ina219_ready = 0U;
            Measurement_SetInvalid("CONVERSION_TIMEOUT");
        }
        return;
    }

    /* OVF applies to INA219's internally calibrated Current/Power math.
       This program calculates I and P from raw shunt voltage, so it does not
       use that flag as a validity test. */

    status = INA219_ReadRegister(INA219_REG_SHUNT, &shunt_raw_u);
    if (status != HAL_OK)
    {
        g_ina219_ready = 0U;
        Measurement_SetInvalid("I2C_SHUNT");
        return;
    }

    shunt_raw = (int16_t)shunt_raw_u;

    /* Shunt register: signed 16-bit, 10uV/LSB. Rshunt is expressed in mΩ. */
    shunt_uV = (int64_t)shunt_raw * 10LL;
    current_uA = (shunt_uV * 1000LL) / (int64_t)RSHUNT_MOHM;

    last_shunt_raw = shunt_raw;
    last_raw_uA = (int32_t)current_uA;
    last_raw_tick = now;
    have_raw_sample = true;
    current_uA -= CURRENT_OFFSET_UA;
    if (current_uA >= -CURRENT_ZERO_BAND_UA && current_uA <= CURRENT_ZERO_BAND_UA)
        current_uA = 0;
    if (current_uA < 0) { Measurement_SetInvalid("NEGATIVE_CURRENT"); return; }
    if (current_uA > 999999) { Measurement_SetInvalid("CURRENT_RANGE"); return; }
    if (((bus_raw >> 3U) & 0x1FFFU)*4U > 26000U) { Measurement_SetInvalid("BUS_RANGE"); return; }
    abs_current_uA = (uint64_t)current_uA;
    current_sq = abs_current_uA * abs_current_uA;

    /* P[uW] = I[uA]^2 * R[mΩ] / 1e9 */
    power_uW = (current_sq * (uint64_t)g_rload_mohm) / 1000000000ULL;

    if (power_uW > 999999ULL) { Measurement_SetInvalid("POWER_RANGE"); return; }
    g_measurement.vbus_mV = (uint32_t)(((bus_raw >> 3U) & 0x1FFFU) * 4U);
    g_measurement.current_uA = (int32_t)current_uA;
    g_measurement.power_uW = power_uW;
    g_measurement.sample_tick_ms = now;
    sensor_reason = "OK";
    g_measurement.valid = 1U;

    Measurement_t sample = g_measurement;
    sample.sample_tick_ms = g_sensor_trigger_tick;
    Energy_IntegrateSample(&sample);

    g_sensor_conversion_pending = 0U;
    g_sensor_generation++;
}

static void INA219_Task(uint32_t now)
{
    if (g_ina219_ready == 0U)
    {
        if ((uint32_t)(now - g_sensor_last_retry_tick) >= SENSOR_RETRY_MS)
        {
            g_sensor_last_retry_tick = now;
            if (INA219_Init())
            {
                g_next_sensor_tick = now;
            }
        }
        return;
    }

    if (g_sensor_conversion_pending != 0U)
    {
        if ((uint32_t)(now - g_sensor_trigger_tick) >= SENSOR_CONVERT_WAIT_MS)
        {
            INA219_FinishConversion(now);
        }
        return;
    }

    if (TickDue(now, g_next_sensor_tick))
    {
        g_next_sensor_tick += SENSOR_PERIOD_MS;
        if ((int32_t)(now - g_next_sensor_tick) > (int32_t)SENSOR_PERIOD_MS)
        {
            g_next_sensor_tick = now + SENSOR_PERIOD_MS;
        }
        INA219_StartConversion(now);
    }
}

/* -------------------------------------------------------------------------- */
/* UART ring queue                                                             */
/* -------------------------------------------------------------------------- */

static void ByteRing_PushFromISR(ByteRing_t *ring, uint8_t byte)
{
    uint16_t head = ring->head;
    uint16_t used = (uint16_t)(head - ring->tail);

    if (used >= RX_RING_SIZE)
    {
        ring->dropped++;
        return;
    }

    ring->data[head & RX_RING_MASK] = byte;
    ring->head = (uint16_t)(head + 1U);
}

static bool ByteRing_Pop(ByteRing_t *ring, uint8_t *byte)
{
    uint16_t tail = ring->tail;

    if (tail == ring->head)
    {
        return false;
    }

    *byte = ring->data[tail & RX_RING_MASK];
    ring->tail = (uint16_t)(tail + 1U);
    return true;
}

static void TxRing_KickLocked(TxRing_t *ring, UART_HandleTypeDef *huart)
{
    uint32_t used;
    uint32_t tail;
    uint16_t index;
    uint16_t contiguous;

    if (ring->busy != 0U)
    {
        return;
    }

    used = ring->head - ring->tail;
    if (used == 0U)
    {
        return;
    }

    tail = ring->tail;
    index = (uint16_t)(tail & TX_RING_MASK);
    contiguous = (uint16_t)(TX_RING_SIZE - index);
    if (used < contiguous)
    {
        contiguous = (uint16_t)used;
    }

    ring->active_chunk = contiguous;
    ring->busy = 1U;
    if (HAL_UART_Transmit_IT(huart, &ring->data[index], contiguous) != HAL_OK)
    {
        ring->busy = 0U;
    }
}

static void TxRing_Kick(TxRing_t *ring, UART_HandleTypeDef *huart)
{
    uint32_t mask=__get_PRIMASK(); __disable_irq();
    TxRing_KickLocked(ring,huart); __set_PRIMASK(mask);
}

static bool TxRing_Queue(TxRing_t *ring, UART_HandleTypeDef *huart,
                         const uint8_t *data, uint16_t length)
{
    uint32_t head;
    uint32_t used;
    uint16_t i;

    if ((data == NULL) || (length == 0U))
    {
        return false;
    }

    head = ring->head;
    used = head - ring->tail;
    if ((uint32_t)length > (TX_RING_SIZE - used))
    {
        ring->dropped++;
        return false;
    }

    for (i = 0U; i < length; i++)
    {
        ring->data[(head + i) & TX_RING_MASK] = data[i];
    }
    ring->head = head + length;
    TxRing_Kick(ring, huart);
    return true;
}

static bool PC_SendText(const char *text)
{
    if (text == NULL)
    {
        return false;
    }
    return TxRing_Queue(&pc_tx_ring, &ECE2_PC_UART_HANDLE,
                        (const uint8_t *)text, (uint16_t)strlen(text));
}

static bool FPGA_SendText(const char *text)
{
    if (text == NULL)
    {
        return false;
    }
    return TxRing_Queue(&fpga_tx_ring, &ECE2_FPGA_UART_HANDLE,
                        (const uint8_t *)text, (uint16_t)strlen(text));
}

/* -------------------------------------------------------------------------- */
/* ASCII frame helper: XOR checksum                                            */
/* -------------------------------------------------------------------------- */

static uint8_t Frame_Xor(const char *text, size_t length)
{
    uint8_t value = 0U;
    size_t i;

    for (i = 0U; i < length; i++)
    {
        value ^= (uint8_t)text[i];
    }
    return value;
}

static bool Frame_AppendChecksum(char *buffer, size_t buffer_size)
{
    size_t length;
    uint8_t checksum;
    int written;

    if (buffer == NULL)
    {
        return false;
    }

    length = strlen(buffer);
    checksum = Frame_Xor(buffer + 1, length - 1);
    written = snprintf(buffer + length, buffer_size - length,
                       "*%02X\n", checksum);
    return (written > 0) && ((size_t)written < (buffer_size - length));
}

static bool Frame_CheckChecksum(char *line)
{
    char *star;
    char *endptr;
    unsigned long received;
    uint8_t calculated;

    star = strchr(line, '*');
    if ((star == NULL) || (strlen(star + 1) != 2U))
    {
        return false;
    }

    received = strtoul(star + 1, &endptr, 16);
    if ((*endptr != '\0') || (received > 0xFFUL))
    {
        return false;
    }

    calculated = Frame_Xor(line + 1, (size_t)(star - line - 1));
    return (calculated == (uint8_t)received);
}


/* Shared ASCII protocol: $T/$M/$S, seq/id hex4, energies in uWh. */

static void U64Fixed12(uint64_t n,char out[13]) {
    out[12]=0; for(int i=11;i>=0;i--) {out[i]=(char)('0'+n%10);n/=10;}
}

static bool FPGA_SendTimeFrame(void)
{
    DateTime_t dt; char frame[96]; bool valid=RTC_ReadDateTime(&dt);
    g_rtc_valid=valid;
    if(valid) snprintf(frame,sizeof frame,"$T,%04X,%04u%02u%02u,%02u%02u%02u,%u,1",
        (unsigned)((g_fpga_tx_seq+1U)&0xffffU),dt.year,dt.month,dt.day,dt.hour,dt.minute,dt.second,dt.weekday);
    else snprintf(frame,sizeof frame,"$T,%04X,00000000,000000,0,0",(unsigned)((g_fpga_tx_seq+1U)&0xffffU));
    bool sent=Frame_AppendChecksum(frame,sizeof frame) && FPGA_SendText(frame);
    if(sent)g_fpga_tx_seq++;
    return sent;
}
static bool FPGA_SendMeasurementFrame(bool final)
{
    const Measurement_t *sample = final ? &g_run_sample : &g_measurement;
    char frame[128];
    uint8_t valid = sample->valid;
    uint64_t total = g_etotal_2nJ / 7200000ULL;
    uint64_t session = g_esession_2nJ / 7200000ULL;
    if (total > 999999999999ULL || session > 999999999999ULL) valid = 0;
    char et[13], es[13];
    U64Fixed12(total <= 999999999999ULL ? total : 0, et);
    U64Fixed12(session <= 999999999999ULL ? session : 0, es);
    snprintf(frame, sizeof frame, "$%c,%04X,%04X,%05lu,%06lu,%06lu,%s,%s,%u,%u",
             final ? 'F' : 'M', (unsigned)((g_fpga_measure_seq + 1U) & 0xffffU), g_run_id,
             (unsigned long)(valid ? sample->vbus_mV : 0),
             (unsigned long)(valid ? sample->current_uA : 0),
             (unsigned long)(valid ? sample->power_uW : 0), et, es,
             (unsigned)valid, final ? (unsigned)!g_session_partial : (unsigned)g_session_ack);
    bool sent = Frame_AppendChecksum(frame, sizeof frame) && FPGA_SendText(frame);
    if (sent && !final)
    {
        g_fpga_measure_seq++;
        if (valid && g_arm_phase == 1) { g_arm_phase = 2; g_session_ack = 1; }
    }
    return sent;
}

/* Human-readable PC serial output. */
static void FormatMilliSigned(int64_t value_milli, char *out, size_t out_size)
{
    uint64_t abs_value = (uint64_t)((value_milli < 0) ? -value_milli : value_milli);
    (void)snprintf(out, out_size, "%s%lu.%03lu",
                   (value_milli < 0) ? "-" : "",
                   (unsigned long)(abs_value / 1000ULL),
                   (unsigned long)(abs_value % 1000ULL));
}

static void FormatEnergy_mWh(uint64_t energy_2nJ, char *out, size_t out_size)
{
    /* 1mWh = 3.6e9nJ; 0.001mWh = 3.6e6nJ = 7.2e6 in 2nJ units. */
    uint64_t milli_mWh = energy_2nJ / 7200000ULL;
    (void)snprintf(out, out_size, "%lu.%03lu",
                   (unsigned long)(milli_mWh / 1000ULL),
                   (unsigned long)(milli_mWh % 1000ULL));
}

static bool PC_SendReport(bool final)
{
    const Measurement_t *sample = &g_measurement;
    if (final) sample = &g_run_sample;
    else if (g_session_running) sample = g_pending_sample.valid ? &g_pending_sample : &g_run_sample;
    DateTime_t dt;
    char clock[32] = "RTC UNSET";
    char volts[24] = "--", amps[24] = "--", power[24] = "--";
    char energy[32], total[32], report[256];
    if (RTC_ReadDateTime(&dt))
        snprintf(clock, sizeof clock, "%04u-%02u-%02u %02u:%02u:%02u",
                 dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second);
    bool valid = sample->valid && (final || g_measurement.valid);
    if (valid)
    {
        FormatMilliSigned(sample->vbus_mV, volts, sizeof volts);
        FormatMilliSigned(sample->current_uA, amps, sizeof amps);
        FormatMilliSigned((int64_t)sample->power_uW, power, sizeof power);
    }
    FormatEnergy_mWh(g_esession_2nJ, energy, sizeof energy);
    FormatEnergy_mWh(g_etotal_2nJ, total, sizeof total);
    const char *gate = !g_fpga_state_known ? "?" : g_fpga_gate_cmd ? "ON" : "OFF";
    const char *quality = final && g_session_partial ? "PARTIAL" : valid ? "VALID" : "NO DATA";
    int length = snprintf(report, sizeof report,
                          "%s\r\n%u %s | %s | Gate %s | %s\r\n"
                          "V %s V | I %s mA | P %s mW | E %s mWh | Total %s mWh\r\n",
                          clock, (unsigned)g_fpga_state_number, g_fpga_state, g_fpga_reason,
                          gate, quality, volts, amps, power, energy, total);
    return length > 0 && (size_t)length < sizeof report &&
        TxRing_Queue(&pc_tx_ring, &ECE2_PC_UART_HANDLE, (const uint8_t *)report, (uint16_t)length);
}

/* Parse decimal ohms to integer milliohms, with at most three decimal places. */
static bool ParseLoadOhms(const char *text, uint32_t *mohm)
{
    if (*text < '0' || *text > '9') return false;
    uint32_t whole = 0U, fractional = 0U, scale = 100U;
    while (*text >= '0' && *text <= '9')
    {
        whole = whole * 10U + (uint32_t)(*text++ - '0');
        if (whole > 1000U) return false;
    }
    if (*text == '.')
    {
        text++;
        if (*text < '0' || *text > '9') return false;
        while (scale && *text >= '0' && *text <= '9')
        {
            fractional += scale * (uint32_t)(*text++ - '0');
            scale /= 10U;
        }
    }
    uint32_t value = whole * 1000U + fractional;
    if (*text || value < 1000U || value > 1000000U) return false;
    *mohm = value;
    return true;
}

static void PC_SendAck(const char *message)
{
    char line[128];
    (void)snprintf(line, sizeof(line), "ACK,%s\r\n", message);
    (void)PC_SendText(line);
}

static void PC_SendError(const char *message)
{
    char line[128];
    (void)snprintf(line, sizeof(line), "ERR,%s\r\n", message);
    (void)PC_SendText(line);
}

static bool FPGA_IsConfirmedOff(void)
{
    return ((g_fpga_state_known != 0U) && (HAL_GetTick()-g_last_s_tick<=1000U) &&
            (g_fpga_gate_cmd == 0U) &&
            ((strcmp(g_fpga_state, "IDLE") == 0) ||
             (strcmp(g_fpga_state, "DONE") == 0) ||
             (strcmp(g_fpga_state, "FAULT") == 0)));
}

static void PC_ProcessCommand(char *line)
{
    unsigned int year, month, day, hour, minute, second;
    char extra;
    int count;

    while ((*line != '\0') && isspace((unsigned char)*line)) line++;
    if (*line == '\0') return;

    if (strncmp(line, "TIME,", 5U) == 0)
    {
        count = sscanf(line, "TIME,%u,%u,%u,%u,%u,%u%c",
                       &year, &month, &day, &hour, &minute, &second, &extra);
        if ((count != 6) || (year < 2000U) || (year > 2099U) ||
            (month > 255U) || (day > 255U) || (hour > 255U) ||
            (minute > 255U) || (second > 255U))
        {
            PC_SendError("TIME_FORMAT");
            return;
        }

        if (!RTC_SetDateTime((uint16_t)year, (uint8_t)month, (uint8_t)day,
                             (uint8_t)hour, (uint8_t)minute, (uint8_t)second))
        {
            PC_SendError("RTC_SET_FAILED_CHECK_LSE");
            g_rtc_valid = 0U;
            return;
        }

        g_rtc_valid = 1U;
        PC_SendAck("TIME_SET");
        return;
    }

    if (strcmp(line, "SENSOR?") == 0)
    {
        char reply[160];
        if (have_raw_sample)
            snprintf(reply, sizeof reply,
                     "SENSOR,last_shunt=%d,raw_uA=%ld,age_ms=%lu,valid=%u,reason=%s\r\n",
                     (int)last_shunt_raw, (long)last_raw_uA,
                     (unsigned long)(HAL_GetTick() - last_raw_tick),
                     (unsigned)g_measurement.valid, sensor_reason);
        else
            snprintf(reply, sizeof reply, "SENSOR,no_sample,valid=0,reason=%s\r\n", sensor_reason);
        (void)PC_SendText(reply);
        return;
    }
    if (strcmp(line, "GET") == 0)
    {
        DateTime_t dt;
        char response[96];
        if (RTC_ReadDateTime(&dt))
        {
            (void)snprintf(response, sizeof(response),
                           "TIME,%04u,%02u,%02u,%02u,%02u,%02u\r\n",
                           dt.year, dt.month, dt.day,
                           dt.hour, dt.minute, dt.second);
            (void)PC_SendText(response);
        }
        else
        {
            PC_SendError("RTC_INVALID");
        }
        return;
    }

    if (strncmp(line, "RLOAD,", 6U) == 0)
    {
        uint32_t run_res;
        if (!ParseLoadOhms(line + 6, &run_res))
        {
            PC_SendError("RLOAD_EXPECT_OHM_1_TO_1000");
            return;
        }
        if (!FPGA_IsConfirmedOff() || (g_session_active != 0U))
        {
            PC_SendError("RLOAD_CHANGE_ONLY_WHEN_OFF");
            return;
        }
        g_rload_mohm = run_res;
        PC_SendAck("RLOAD_SET_OHM");
        return;
    }

    if (strcmp(line, "CLEAR_ENERGY") == 0)
    {
        if ((!FPGA_IsConfirmedOff()) || (g_session_active != 0U))
        {
            PC_SendError("CLEAR_ONLY_WHEN_FPGA_CONFIRMS_OFF");
            return;
        }

        g_etotal_2nJ = 0ULL;
        /* Keep the last session result; only the lifetime total is cleared. */
        PC_SendAck("ENERGY_CLEARED");
        return;
    }

    PC_SendError("UNKNOWN_COMMAND");
}

/* -------------------------------------------------------------------------- */
/* FPGA 수신 프레임 처리                                                       */
/* -------------------------------------------------------------------------- */


static void FPGA_ProcessFrame(char *line)
{
    unsigned seq,id,state,remain,gate,reason; int used=0;
    static const char *states[]={"IDLE","WAIT","RUN","DONE","ARM","FAULT"};
    static const char *reasons[]={"NONE","TIME","CANCEL","SENSOR","TIMEOUT","ARM_TIMEOUT","CONFIG","SESSION"};
    if(strlen(line)!=27 || line[0]!='$' || line[1]!='S' || !Frame_CheckChecksum(line)) return;
    const unsigned comma[]={2,7,12,14,20,22};
    for(unsigned j=0;j<6;j++)if(line[comma[j]]!=',')return;
    if(line[24]!='*')return;
    for(unsigned j=3;j<24;j++) {
        if(j==7||j==12||j==14||j==20||j==22)continue;
        bool hex=(j>=3&&j<=6)||(j>=8&&j<=11);
        if(hex ? !((line[j]>='0'&&line[j]<='9')||(line[j]>='A'&&line[j]<='F')) : !isdigit((unsigned char)line[j]))return;
    }
    if(sscanf(line,"$S,%4x,%4x,%1u,%5u,%1u,%1u%n",&seq,&id,&state,&remain,&gate,&reason,&used)!=6 || used!=24 || state>5 || gate>1 || reason>7 || (gate && state!=2))return;
    uint16_t delta=(uint16_t)(seq-g_last_s_seq);
    if (g_pc_final_pending || (g_have_s && (delta==0 || delta>=0x8000U))) return;
    uint32_t now = HAL_GetTick();
    g_have_s = 1; g_last_s_seq = (uint16_t)seq; g_last_s_tick = now;
    g_fpga_state_known = 1; g_fpga_gate_cmd = (uint8_t)gate;
    g_fpga_state_number = (uint8_t)state;
    strcpy(g_fpga_state, states[state]);
    strcpy(g_fpga_reason, reasons[reason]);
    if (g_session_active && ((uint16_t)id != g_run_id || state == 0 || state == 3 || state == 5))
        Session_Finish(now - FPGA_STATUS_WIRE_MS, state == 3 && reason == 1 && (uint16_t)id == g_run_id);

    if (state == 4 && !g_session_active && !g_pc_final_pending && g_arm_phase == 0 &&
        g_measurement.valid && now - g_measurement.sample_tick_ms <= MAX_INTEGRATE_GAP_MS)
    {
        g_run_id = (uint16_t)id;
        g_esession_2nJ = 0;
        g_session_active = true;
        g_session_partial = false;
        g_session_final = false;
        g_run_sample.valid = 0;
        g_pending_sample.valid = 0;
        g_session_ack = 0; g_arm_phase = 1;
        g_next_fpga_meas_tick = now;
        g_last_m_generation = g_sensor_generation - 1U;
    }
    if (state != 4) g_arm_phase = 0;
    if (!g_session_active || (uint16_t)id != g_run_id) return;

    if ((state == 1 || state == 2) && !g_pc_report_active)
    {
        g_pc_report_active = true;
        g_next_pc_log_tick = now;
    }
    if (state == 2 && gate && !g_session_running)
    {
        g_session_running = true;
        g_run_start_tick = now - FPGA_STATUS_WIRE_MS;
    }
}

/* -------------------------------------------------------------------------- */
/* RX ring -> line parser                                                      */
/* -------------------------------------------------------------------------- */

static void UART_ProcessRxLines(void)
{
    uint8_t byte;

    while (ByteRing_Pop(&pc_rx_ring, &byte))
    {
        if ((byte == '\r') || (byte == '\n'))
        {
            if (!pc_line_discard && pc_line_len > 0U)
            {
                pc_line[pc_line_len] = '\0';
                PC_ProcessCommand(pc_line);
            }
            pc_line_len = 0U;
            pc_line_discard = false;
        }
        else if (!pc_line_discard && pc_line_len < (PC_LINE_SIZE - 1U))
        {
            pc_line[pc_line_len++] = (char)byte;
        }
        else if (!pc_line_discard)
        {
            pc_line_discard = true;
            PC_SendError("PC_LINE_TOO_LONG");
        }
    }

    while (ByteRing_Pop(&fpga_rx_ring, &byte))
    {
        if(byte=='$')fpga_line_len=0;
        if ((byte == '\r') || (byte == '\n'))
        {
            if (fpga_line_len > 0U)
            {
                char *star;
                fpga_line[fpga_line_len] = '\0';
                star = strchr(fpga_line, '*');
                if (star != NULL)
                {
                    FPGA_ProcessFrame(fpga_line);
                }
                fpga_line_len = 0U;
            }
        }
        else if (fpga_line_len < (FPGA_LINE_SIZE - 1U))
        {
            fpga_line[fpga_line_len++] = (char)byte;
        }
        else
        {
            fpga_line_len = 0U;
        }
    }
}

/* -------------------------------------------------------------------------- */
/* 과제 템플릿에서 호출하는 초기화/폴링/ISR 함수                               */
/* -------------------------------------------------------------------------- */

void ece2_474_init(void)
{
    uint32_t now = HAL_GetTick();

    /* UART 인터럽트 수신 시작: PC=USART2, FPGA=USART3 */
    (void)HAL_UART_Receive_IT(&ECE2_PC_UART_HANDLE, &uart2_rx_ece2, 1U);
    (void)HAL_UART_Receive_IT(&ECE2_FPGA_UART_HANDLE, &uart3_rx_ece2, 1U);

    /* LSE/RTC clock을 준비합니다. 이미 초기화된 달력은 덮어쓰지 않습니다. */
    {
        DateTime_t dt;
        g_rtc_clock_ready = RTC_ClockInit() ? 1U : 0U;
        g_rtc_valid = ((g_rtc_clock_ready != 0U) && RTC_ReadDateTime(&dt)) ? 1U : 0U;
    }

    /* INA219 확인 */
    g_sensor_last_retry_tick = now;
    if (INA219_Init())
    {
        g_next_sensor_tick = now;
    }
    else
    {
        g_ina219_ready = 0U;
        Measurement_SetInvalid("I2C_INIT");
    }

    now=HAL_GetTick();
    g_next_fpga_meas_tick = now + FPGA_MEAS_PERIOD_MS;
    g_next_fpga_time_tick = now + FPGA_TIME_PERIOD_MS;
    g_next_pc_log_tick = now + PC_LOG_PERIOD_MS;

    PC_SendAck(g_rtc_valid ? "STM32_READY_RTC_VALID" : "STM32_READY_RTC_UNSET");
}

void polling_routine(void)
{
    UART_ProcessRxLines();
    uint32_t now = HAL_GetTick();
    if (g_have_s && now - g_last_s_tick > 1000U)
    {
        g_fpga_state_known = 0;
        g_session_ack = 0; g_arm_phase = 0; g_have_s = 0;
        g_fpga_state_number = 5;
        strcpy(g_fpga_state, "FAULT");
        strcpy(g_fpga_reason, "LINK_TIMEOUT");
        g_integrate_previous = false;
        g_pending_sample.valid = 0U;
        if (g_session_active) Session_Finish(now, false);
    }
    INA219_Task(now);
    if (g_measurement.valid && now - g_measurement.sample_tick_ms > MAX_INTEGRATE_GAP_MS)
        Measurement_SetInvalid("STALE");

    if (TickDue(now, g_next_fpga_time_tick))
    {
        g_next_fpga_time_tick += FPGA_TIME_PERIOD_MS;
        if ((int32_t)(now - g_next_fpga_time_tick) > (int32_t)FPGA_TIME_PERIOD_MS)
        {
            g_next_fpga_time_tick = now + FPGA_TIME_PERIOD_MS;
        }
        FPGA_SendTimeFrame();
    }

    if (TickDue(now, g_next_fpga_meas_tick))
    {
        g_next_fpga_meas_tick += FPGA_MEAS_PERIOD_MS;
        if ((int32_t)(now - g_next_fpga_meas_tick) > (int32_t)FPGA_MEAS_PERIOD_MS)
        {
            g_next_fpga_meas_tick = now + FPGA_MEAS_PERIOD_MS;
        }

        if (g_sensor_generation != g_last_m_generation)
        {
            if (FPGA_SendMeasurementFrame(false)) g_last_m_generation = g_sensor_generation;
        }
        if (g_session_final && g_fpga_state_known && !g_session_active)
            FPGA_SendMeasurementFrame(true);
    }

    if (g_pc_final_pending)
    {
        if (PC_SendReport(true))
        {
            g_pc_final_pending = false;
            g_pc_report_active = false;
        }
    }
    else if (g_pc_report_active && TickDue(now, g_next_pc_log_tick))
    {
        if (PC_SendReport(false)) g_next_pc_log_tick = now + PC_LOG_PERIOD_MS;
    }

    /* TX queue에서 HAL_BUSY 등으로 시작되지 못한 송신을 다시 시도합니다. */
    TxRing_Kick(&pc_tx_ring, &ECE2_PC_UART_HANDLE);
    TxRing_Kick(&fpga_tx_ring, &ECE2_FPGA_UART_HANDLE);
}

static void button_isr_p7(void)
{
    /* 사용자 버튼은 이 담당 기능에 직접 할당하지 않습니다. 필요하면 flag만 설정하세요. */
}

static void tim6_isr_p4(void)
{
    /* 이번 구현은 HAL_GetTick() 기반 주기 실행이므로 TIM6를 시작하지 않습니다. */
}

static void uart2_isr_p6(void)
{
    ByteRing_PushFromISR(&pc_rx_ring, uart2_rx_ece2);
    (void)HAL_UART_Receive_IT(&ECE2_PC_UART_HANDLE, &uart2_rx_ece2, 1U);
}

static void uart3_isr_p5(void)
{
    ByteRing_PushFromISR(&fpga_rx_ring, uart3_rx_ece2);
    (void)HAL_UART_Receive_IT(&ECE2_FPGA_UART_HANDLE, &uart3_rx_ece2, 1U);
}

static void gpio_in_pullup_isr_p8_ece2(void)
{
    /* 현재 STM32 담당 과제에서 사용하지 않습니다. */
}

static void gpio_in_pulldown_isr_p9_ece2(void)
{
    /* 현재 STM32 담당 과제에서 사용하지 않습니다. */
}

/* -------------------------------------------------------------------------- */
/* HAL callbacks                                                               */
/* -------------------------------------------------------------------------- */

void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)
{
    if (GPIO_Pin == BUTTON_ece2_Pin)
    {
        button_isr_p7();
    }
    else if (GPIO_Pin == GPIO_IN_PULLUP_ece2_Pin)
    {
        gpio_in_pullup_isr_p8_ece2();
    }
    else if (GPIO_Pin == GPIO_IN_PULLDOWN_ece2_Pin)
    {
        gpio_in_pulldown_isr_p9_ece2();
    }
}

void HAL_TIM_PeriodElapsedCallback(TIM_HandleTypeDef *htim)
{
    if (htim->Instance == TIM6)
    {
        tim6_isr_p4();
    }
}

void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance == USART2)
    {
        uart2_isr_p6();
    }
    else if (huart->Instance == USART3)
    {
        uart3_isr_p5();
    }
}

void HAL_UART_TxCpltCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance == USART2)
    {
        pc_tx_ring.tail += pc_tx_ring.active_chunk;
        pc_tx_ring.busy = 0U;
        TxRing_Kick(&pc_tx_ring, &ECE2_PC_UART_HANDLE);
    }
    else if (huart->Instance == USART3)
    {
        fpga_tx_ring.tail += fpga_tx_ring.active_chunk;
        fpga_tx_ring.busy = 0U;
        TxRing_Kick(&fpga_tx_ring, &ECE2_FPGA_UART_HANDLE);
    }
}


void HAL_UART_ErrorCallback(UART_HandleTypeDef *huart)
{
    __HAL_UART_CLEAR_FLAG(huart, UART_CLEAR_OREF | UART_CLEAR_FEF | UART_CLEAR_NEF);
    if(huart->Instance==USART2) {pc_rx_ring.dropped++;HAL_UART_Receive_IT(huart,&uart2_rx_ece2,1);}
    else if(huart->Instance==USART3) {fpga_rx_ring.dropped++;HAL_UART_Receive_IT(huart,&uart3_rx_ece2,1);}
}
