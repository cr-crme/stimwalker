from time import sleep
import logging

import numpy as np
from matplotlib import pyplot as plt
from lokomat_fes import setup_logger, Data
from lokomat_fes.runner import RunnerConsole
from lokomat_fes.nidaq import NiDaqLokomat
from lokomat_fes.rehastim import RehastimLokomat

# If you want to use the real devices, comment the following lines
from lokomat_fes.nidaq.mocks import NiDaqLokomatMock as NiDaqLokomat
from lokomat_fes.rehastim.mocks import RehastimLokomatMock as RehastimLokomat


def _received_data(t: np.ndarray, data: np.ndarray) -> None:
    """Callback function that is called when new nidaq data are received"""

    t_index = 0
    hip_index = 0
    print(f"Received data, at {t[t_index]}, initial hip angle: {data[hip_index, t_index]}")


def plot_data(data: Data) -> None:
    nidaq_data = data.nidaq
    rehastim_data = data.rehastim

    plt.figure("Data against time")

    # On left-hand side axes, plot nidaq data
    color = "blue"
    ax1 = plt.axes()
    ax1.set_xlabel(f"Time [s] (first sample at {nidaq_data.t0})")
    ax1.set_ylabel("Data [mV]", color=color)
    ax1.tick_params(axis="y", labelcolor=color)
    plt.plot(nidaq_data.time, nidaq_data.as_array.T, color=color)

    # On right-hand side axes, plot rehastim data as stair data (from t0 to duration at height of amplitude)
    color = "red"
    ax2 = ax1.twinx()
    ax2.set_ylabel("Amplitude [mA]", color=color)
    ax2.tick_params(axis="y", labelcolor=color)
    all_time = rehastim_data.time
    all_duration = rehastim_data.duration_as_array
    all_amplitude = rehastim_data.amplitude_as_array.T
    for time, duration, amplitude in zip(all_time, all_duration, all_amplitude):
        channel_index = 0  # Only show the first channel as they are all the same (currently)
        plt.plot([time, time + duration], amplitude[[channel_index, channel_index]], color=color)

    plt.show()


def __main__() -> None:
    setup_logger(level=logging.WARNING)  # Change to logging.INFO to see more logs

    # Define the devices and the runner
    rehastim = RehastimLokomat()
    nidaq = NiDaqLokomat()
    runner = RunnerConsole(rehastim, nidaq)

    # Start the runner (blocking)
    runner.exec()

    # Alternatively, you can use a blocking sleep to manually manage the devices
    # Start the devices (only necessary if you start manually)
    # nidaq.start_recording()
    # nidaq.register_to_data_ready(_received_data)  # This is to monitor the data. Note you can do that even when using exec()
    # sleep(1)
    # Stop the devices (only necessary if you start manually)
    # nidaq.stop_recording()
    # rehastim.stop_stimulation()

    # Get the last recorded data (includes Nidaq and Rehastim data)
    # Preferably, this is managed inside the runner, but you can do it manually (only for last trial though)
    data = runner.last_trial
    if data is not None:
        # You can also save and reload
        data.save("data.pkl")
        data_loaded = Data.load("data.pkl")

        # You can plot pretty easily, note that data_loaded is a valid class instance like the data
        plot_data(data_loaded)

    # Dispose the devices (this is important to avoid memory leaks and stop subprocesses)
    nidaq.dispose()
    rehastim.dispose()


if __name__ == "__main__":
    __main__()
