from aw_watcher_system.windows import CpuTimes, calculate_cpu_percent


def test_calculate_cpu_percent():
    previous = CpuTimes(idle=100, total=1000)
    current = CpuTimes(idle=250, total=2000)

    assert calculate_cpu_percent(previous, current) == 85.0


def test_calculate_cpu_percent_clamps_negative_busy_time():
    previous = CpuTimes(idle=100, total=1000)
    current = CpuTimes(idle=1200, total=2000)

    assert calculate_cpu_percent(previous, current) == 0.0


def test_calculate_cpu_percent_handles_zero_total_delta():
    sample = CpuTimes(idle=100, total=1000)

    assert calculate_cpu_percent(sample, sample) == 0.0
