import ctypes
import sys
import uuid
from ctypes import wintypes
from typing import Dict, Iterable, List, Optional, Set

from .state import EndpointLevel

if sys.platform == "win32":
    ole32 = ctypes.WinDLL("ole32", use_last_error=True)
else:
    ole32 = None

HRESULT = ctypes.c_long
COINIT_MULTITHREADED = 0
CLSCTX_ALL = 0x17
S_OK = 0
S_FALSE = 1
RPC_E_CHANGED_MODE = ctypes.c_int32(0x80010106).value

E_RENDER = 0
E_CAPTURE = 1

ROLES = {
    "console": 0,
    "multimedia": 1,
    "communications": 2,
}

FLOWS = {
    "playback": E_RENDER,
    "microphone": E_CAPTURE,
}


class GUID(ctypes.Structure):
    _fields_ = [
        ("Data1", wintypes.DWORD),
        ("Data2", wintypes.WORD),
        ("Data3", wintypes.WORD),
        ("Data4", ctypes.c_ubyte * 8),
    ]

    def __init__(self, value: str):
        guid = uuid.UUID(value)
        data4 = bytes([guid.clock_seq_hi_variant, guid.clock_seq_low]) + guid.node.to_bytes(
            6, "big"
        )
        super().__init__(
            guid.time_low,
            guid.time_mid,
            guid.time_hi_version,
            (ctypes.c_ubyte * 8).from_buffer_copy(data4),
        )


CLSID_MMDEVICE_ENUMERATOR = GUID("{BCDE0395-E52F-467C-8E3D-C4579291692E}")
IID_IMMDEVICE_ENUMERATOR = GUID("{A95664D2-9614-4F35-A746-DE8DB63617E6}")
IID_IAUDIO_METER_INFORMATION = GUID("{C02216F6-8C67-4B5B-9D00-D008E73E0064}")


class AudioApiError(RuntimeError):
    pass


if ole32 is not None:
    ole32.CoInitializeEx.argtypes = [wintypes.LPVOID, wintypes.DWORD]
    ole32.CoInitializeEx.restype = HRESULT
    ole32.CoUninitialize.argtypes = []
    ole32.CoUninitialize.restype = None
    ole32.CoCreateInstance.argtypes = [
        ctypes.POINTER(GUID),
        wintypes.LPVOID,
        wintypes.DWORD,
        ctypes.POINTER(GUID),
        ctypes.POINTER(ctypes.c_void_p),
    ]
    ole32.CoCreateInstance.restype = HRESULT
    ole32.CoTaskMemFree.argtypes = [wintypes.LPVOID]
    ole32.CoTaskMemFree.restype = None


def _failed(hr: int) -> bool:
    return int(hr) < 0


def _format_hresult(hr: int) -> str:
    return "0x{0:08X}".format(ctypes.c_uint32(hr).value)


def _check_hresult(hr: int, operation: str):
    if _failed(hr):
        raise AudioApiError(f"{operation} failed with HRESULT {_format_hresult(hr)}")


class ComApartment:
    def __init__(self):
        self._uninitialize = False

    def __enter__(self):
        if ole32 is None:
            raise AudioApiError("Windows Core Audio API is only available on Windows")

        hr = ole32.CoInitializeEx(None, COINIT_MULTITHREADED)
        if hr in (S_OK, S_FALSE):
            self._uninitialize = True
            return self
        if hr == RPC_E_CHANGED_MODE:
            return self
        _check_hresult(hr, "CoInitializeEx")
        return self

    def __exit__(self, exc_type, exc, tb):
        if self._uninitialize:
            ole32.CoUninitialize()


def _call_method(obj, index: int, restype, argtypes, *args):
    vtbl = ctypes.cast(obj, ctypes.POINTER(ctypes.POINTER(ctypes.c_void_p))).contents
    method = ctypes.WINFUNCTYPE(restype, ctypes.c_void_p, *argtypes)(vtbl[index])
    return method(obj, *args)


def _release(obj):
    if obj:
        _call_method(obj, 2, wintypes.ULONG, [])


def _create_enumerator():
    enumerator = ctypes.c_void_p()
    hr = ole32.CoCreateInstance(
        ctypes.byref(CLSID_MMDEVICE_ENUMERATOR),
        None,
        CLSCTX_ALL,
        ctypes.byref(IID_IMMDEVICE_ENUMERATOR),
        ctypes.byref(enumerator),
    )
    _check_hresult(hr, "CoCreateInstance(IMMDeviceEnumerator)")
    return enumerator


def _get_default_endpoint(enumerator, flow: int, role: int):
    device = ctypes.c_void_p()
    hr = _call_method(
        enumerator,
        4,
        HRESULT,
        [ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.c_void_p)],
        flow,
        role,
        ctypes.byref(device),
    )
    if _failed(hr):
        return None
    return device


def _get_device_id(device) -> Optional[str]:
    value = wintypes.LPWSTR()
    hr = _call_method(
        device,
        5,
        HRESULT,
        [ctypes.POINTER(wintypes.LPWSTR)],
        ctypes.byref(value),
    )
    if _failed(hr) or not value:
        return None
    try:
        return value.value
    finally:
        ole32.CoTaskMemFree(value)


def _activate_meter(device):
    meter = ctypes.c_void_p()
    hr = _call_method(
        device,
        3,
        HRESULT,
        [
            ctypes.POINTER(GUID),
            wintypes.DWORD,
            wintypes.LPVOID,
            ctypes.POINTER(ctypes.c_void_p),
        ],
        ctypes.byref(IID_IAUDIO_METER_INFORMATION),
        CLSCTX_ALL,
        None,
        ctypes.byref(meter),
    )
    _check_hresult(hr, "IMMDevice.Activate(IAudioMeterInformation)")
    return meter


def _read_peak(meter) -> float:
    peak = ctypes.c_float()
    hr = _call_method(
        meter,
        3,
        HRESULT,
        [ctypes.POINTER(ctypes.c_float)],
        ctypes.byref(peak),
    )
    _check_hresult(hr, "IAudioMeterInformation.GetPeakValue")
    return min(max(float(peak.value), 0.0), 1.0)


def read_endpoint_levels(roles: Iterable[str]) -> Dict[str, List[EndpointLevel]]:
    levels = {"playback": [], "microphone": []}
    role_names = [role for role in roles if role in ROLES]

    with ComApartment():
        enumerator = _create_enumerator()
        try:
            for flow_name, flow in FLOWS.items():
                seen_devices: Set[str] = set()
                for role_name in role_names:
                    device = _get_default_endpoint(enumerator, flow, ROLES[role_name])
                    if not device:
                        continue
                    try:
                        device_id = _get_device_id(device)
                        dedupe_key = device_id or f"{flow_name}:{role_name}"
                        if dedupe_key in seen_devices:
                            continue
                        seen_devices.add(dedupe_key)

                        meter = _activate_meter(device)
                        try:
                            peak = _read_peak(meter)
                        finally:
                            _release(meter)

                        levels[flow_name].append(
                            EndpointLevel(
                                flow=flow_name,
                                role=role_name,
                                peak=peak,
                                device_id=device_id,
                            )
                        )
                    finally:
                        _release(device)
        finally:
            _release(enumerator)

    return levels

