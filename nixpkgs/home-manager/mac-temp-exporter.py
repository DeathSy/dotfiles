#!/usr/bin/env python3
"""Write Apple silicon CPU temperature to a node_exporter textfile (no root needed).

Reads the "PMU tdie*" (CPU die) sensors through the IOHIDEventSystem API that
monitoring apps such as Stats use, and writes mac_cpu_temp_celsius (hottest die
sensor) atomically to the given .prom path. Usage: mac-temp-exporter <output.prom>
"""

import ctypes
import ctypes.util
import os
import sys

cf = ctypes.CDLL(ctypes.util.find_library("CoreFoundation"))
iokit = ctypes.CDLL(ctypes.util.find_library("IOKit"))
vp, i32, i64 = ctypes.c_void_p, ctypes.c_int32, ctypes.c_int64

cf.CFStringCreateWithCString.restype, cf.CFStringCreateWithCString.argtypes = vp, [vp, ctypes.c_char_p, ctypes.c_uint32]
cf.CFNumberCreate.restype, cf.CFNumberCreate.argtypes = vp, [vp, ctypes.c_long, vp]
cf.CFDictionaryCreate.restype = vp
cf.CFDictionaryCreate.argtypes = [vp, ctypes.POINTER(vp), ctypes.POINTER(vp), ctypes.c_long, vp, vp]
cf.CFArrayGetCount.restype, cf.CFArrayGetCount.argtypes = ctypes.c_long, [vp]
cf.CFArrayGetValueAtIndex.restype, cf.CFArrayGetValueAtIndex.argtypes = vp, [vp, ctypes.c_long]
cf.CFStringGetCString.restype, cf.CFStringGetCString.argtypes = ctypes.c_bool, [vp, ctypes.c_char_p, ctypes.c_long, ctypes.c_uint32]
cf.CFRelease.argtypes = [vp]
cf.CFGetTypeID.restype, cf.CFGetTypeID.argtypes = ctypes.c_ulong, [vp]
cf.CFStringGetTypeID.restype = ctypes.c_ulong
iokit.IOHIDEventSystemClientCreate.restype, iokit.IOHIDEventSystemClientCreate.argtypes = vp, [vp]
iokit.IOHIDEventSystemClientSetMatching.argtypes = [vp, vp]
iokit.IOHIDEventSystemClientCopyServices.restype, iokit.IOHIDEventSystemClientCopyServices.argtypes = vp, [vp]
iokit.IOHIDServiceClientCopyProperty.restype, iokit.IOHIDServiceClientCopyProperty.argtypes = vp, [vp, vp]
iokit.IOHIDServiceClientCopyEvent.restype, iokit.IOHIDServiceClientCopyEvent.argtypes = vp, [vp, i64, i32, i64]
iokit.IOHIDEventGetFloatValue.restype, iokit.IOHIDEventGetFloatValue.argtypes = ctypes.c_double, [vp, i32]

UTF8, SINT32 = 0x08000100, 3
TEMPERATURE_EVENT = 15


def cfstr(s):
    return cf.CFStringCreateWithCString(None, s.encode(), UTF8)


def cfint(n):
    v = ctypes.c_int32(n)
    return cf.CFNumberCreate(None, SINT32, ctypes.byref(v))


def die_temps():
    keys = (vp * 2)(cfstr("PrimaryUsagePage"), cfstr("PrimaryUsage"))
    vals = (vp * 2)(cfint(0xFF00), cfint(5))
    matching = cf.CFDictionaryCreate(None, keys, vals, 2,
                                     ctypes.addressof(ctypes.c_byte.in_dll(cf, "kCFTypeDictionaryKeyCallBacks")),
                                     ctypes.addressof(ctypes.c_byte.in_dll(cf, "kCFTypeDictionaryValueCallBacks")))
    client = iokit.IOHIDEventSystemClientCreate(None)
    if not client or not matching:
        return []
    iokit.IOHIDEventSystemClientSetMatching(client, matching)
    services = iokit.IOHIDEventSystemClientCopyServices(client)
    product, buf, temps = cfstr("Product"), ctypes.create_string_buffer(128), []
    for i in range(cf.CFArrayGetCount(services) if services else 0):
        svc = cf.CFArrayGetValueAtIndex(services, i)
        name = iokit.IOHIDServiceClientCopyProperty(svc, product)
        if not name:
            continue
        if cf.CFGetTypeID(name) != cf.CFStringGetTypeID():
            cf.CFRelease(name)
            continue
        ok = cf.CFStringGetCString(name, buf, len(buf), UTF8)
        cf.CFRelease(name)
        if not ok or not buf.value.startswith(b"PMU tdie"):
            continue
        event = iokit.IOHIDServiceClientCopyEvent(svc, TEMPERATURE_EVENT, 0, 0)
        if event:
            value = iokit.IOHIDEventGetFloatValue(event, TEMPERATURE_EVENT << 16)
            cf.CFRelease(event)
            if 0 < value < 150:
                temps.append(value)
    return temps


def main():
    out = sys.argv[1]
    temps = die_temps()
    lines = ["# HELP mac_cpu_temp_celsius Hottest Apple silicon CPU die sensor (PMU tdie*).",
             "# TYPE mac_cpu_temp_celsius gauge"]
    if temps:
        lines.append(f"mac_cpu_temp_celsius {max(temps):.1f}")
    else:
        print("mac-temp-exporter: no PMU tdie sensors found", file=sys.stderr)
    tmp = f"{out}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    os.replace(tmp, out)


if __name__ == "__main__":
    main()
