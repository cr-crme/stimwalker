import json
import os
import pickle
import numpy as np

from stimwalker import Data
from stimwalker.nidaq.data import NiDaqData
from stimwalker.rehastim.data import RehastimData, Channel


def test_data_creation():
    data = Data()
    assert isinstance(data.nidaq, NiDaqData)
    assert isinstance(data.rehastim, RehastimData)
    assert data.nidaq.t0 == data.t0
    assert data.rehastim.t0 == data.t0


def test_add_nidaq_data():
    data = Data()

    # Add data
    data.nidaq.add(np.array([1]), np.array([[2]]))

    # Check that the data exists
    assert data.nidaq.t0.timestamp() is not None
    assert data.nidaq.time is not None
    assert data.nidaq.as_array is not None


def test_add_rehastim_data():
    data = Data()

    # Add data
    data.rehastim.add(
        now=1, duration=1, channels=(Channel(channel_index=1, amplitude=2), Channel(channel_index=2, amplitude=4))
    )

    # Check that the data exists
    assert data.rehastim.time is not None
    np.testing.assert_almost_equal(data.rehastim.duration_as_array, np.array([1]))
    assert data.rehastim.duration_as_array is not None
    np.testing.assert_almost_equal(data.rehastim.duration_as_array, np.array([1]))
    assert data.rehastim.amplitude_as_array is not None
    np.testing.assert_almost_equal(data.rehastim.amplitude_as_array, np.array([[2, 4]]).T)


def test_copy_data():
    data = Data()

    # Add data
    data.nidaq.add(np.array([1]), np.array([[2]]))
    data.rehastim.add(
        now=1, duration=1, channels=(Channel(channel_index=1, amplitude=2), Channel(channel_index=2, amplitude=4))
    )

    # Copy the data
    data_copy = data.copy

    # Check that the data is correct
    assert data_copy.nidaq.t0 == data.nidaq.t0
    np.testing.assert_almost_equal(data_copy.nidaq.time, data.nidaq.time)
    np.testing.assert_almost_equal(data_copy.nidaq.as_array, data.nidaq.as_array)
    np.testing.assert_almost_equal(data_copy.rehastim.time, data.rehastim.time)
    np.testing.assert_almost_equal(data_copy.rehastim.duration_as_array, data.rehastim.duration_as_array)
    np.testing.assert_almost_equal(data_copy.rehastim.amplitude_as_array, data.rehastim.amplitude_as_array)

    # The copy is a deep copy
    t, d = data_copy.nidaq.sample_block(0, unsafe=True)
    t[0] = 0
    d[0, 0] = 0

    t2, d2 = data_copy.nidaq.sample_block(0, unsafe=True)
    t_orig, d_orig = data.nidaq.sample_block(0, unsafe=True)
    np.testing.assert_almost_equal(t2[0], 0)
    np.testing.assert_almost_equal(d2[0, 0], 0)
    np.testing.assert_almost_equal(t_orig[0], 1)
    np.testing.assert_almost_equal(d_orig[0], 2)


def test_serialize_data():
    data = Data()

    # Add data
    data.nidaq.add(np.array([1]), np.array([[2]]))
    data.rehastim.add(
        now=1, duration=1, channels=(Channel(channel_index=1, amplitude=2), Channel(channel_index=2, amplitude=4))
    )

    # Serialize the data for pickle
    serialized_data = data.serialize()
    assert pickle.dumps(serialized_data)

    # Check that the data is correct
    assert serialized_data["t0"] == data.t0.timestamp()
    assert serialized_data["nidaq"] == data.nidaq.serialize()
    assert serialized_data["rehastim"] == data.rehastim.serialize()

    # Serialize the data for json
    serialized_data = data.serialize(to_json=True)
    assert json.dumps(serialized_data)

    # Check that the data is correct
    assert serialized_data["t0"] == data.t0.timestamp()
    assert serialized_data["nidaq"] == data.nidaq.serialize(to_json=True)
    assert serialized_data["rehastim"] == data.rehastim.serialize(to_json=True)


def test_save_and_load():
    data = Data()

    # Add data
    data.nidaq.add(np.array([1]), np.array([[2]]))
    data.rehastim.add(
        now=1, duration=1, channels=(Channel(channel_index=1, amplitude=2), Channel(channel_index=2, amplitude=4))
    )

    # Save the data
    path = "test_data.pkl"
    data.save(path)

    # Load the data
    data_loaded = Data.load(path)

    # Check that the data is correct
    assert data_loaded.nidaq.t0 == data.nidaq.t0
    np.testing.assert_almost_equal(data_loaded.nidaq.time, data.nidaq.time)
    np.testing.assert_almost_equal(data_loaded.nidaq.as_array, data.nidaq.as_array)
    np.testing.assert_almost_equal(data_loaded.rehastim.time, data.rehastim.time)
    np.testing.assert_almost_equal(data_loaded.rehastim.duration_as_array, data.rehastim.duration_as_array)
    np.testing.assert_almost_equal(data_loaded.rehastim.amplitude_as_array, data.rehastim.amplitude_as_array)

    # Delete the file
    os.remove(path)
