from typing import override

from pyScienceMode.devices.rehastim_generic import RehastimGeneric as pyScienceModeRehastimGeneric
from pyScienceMode.devices.rehastim2 import Rehastim2 as pyScienceModeRehastim2

from .lokomat_rehastim import RehastimLokomat


class PortMock:
    def __init__(self, port: str):
        self.port = port

    def write(self, command: bytes):
        pass

    def close(self):
        pass


class pyScienceModeRehastim2Mock(pyScienceModeRehastim2):
    def _get_last_device_ack(self) -> list:
        return [None, None, None, None, None, 0]

    @override
    def _setup_device(self) -> None:
        self.port = PortMock(port=self.port_name)


class RehastimLokomatMock(RehastimLokomat):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

    @override
    def _get_initialized_device(self) -> pyScienceModeRehastimGeneric:
        return pyScienceModeRehastim2Mock(port=self.port)
