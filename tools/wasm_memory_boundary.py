#!/usr/bin/env python3
"""Read memory limits from actual binary sections, independently of Binaryen."""
import argparse
import hashlib
import json
from pathlib import Path


class Reader:
    def __init__(self, data):
        self.data, self.at = data, 0

    def byte(self):
        if self.at >= len(self.data):
            raise ValueError('truncated module')
        value = self.data[self.at]
        self.at += 1
        return value

    def uint(self, bits=32):
        value = 0
        for shift in range(0, bits, 7):
            byte = self.byte()
            value |= (byte & 127) << shift
            if not byte & 128:
                if value >= 1 << bits:
                    raise ValueError('integer overflow')
                return value
        raise ValueError('unterminated integer')

    def take(self, size):
        if size > len(self.data) - self.at:
            raise ValueError('truncated payload')
        value = self.data[self.at:self.at + size]
        self.at += size
        return value

    def string(self):
        return self.take(self.uint()).decode('utf8')

    def done(self):
        if self.at != len(self.data):
            raise ValueError('unparsed payload')


def limits(reader, memory=True):
    flags = reader.uint()
    if flags & ~7 or (not memory and flags & 2):
        raise ValueError('unsupported limit flags')
    width = 64 if flags & 4 else 32
    minimum = reader.uint(width)
    maximum = reader.uint(width) if flags & 1 else None
    if maximum is not None and minimum > maximum:
        raise ValueError('invalid limits')
    if flags & 2 and maximum is None:
        raise ValueError('shared memory without maximum')
    return {'minimum_pages': minimum, 'maximum_pages': maximum,
            'shared': bool(flags & 2), 'address_bits': width}


def value_type(reader):
    tag = reader.byte()
    if tag in (0x63, 0x64):
        # A heap type is an s33 LEB; only skipping is required here.
        for _ in range(5):
            if not reader.byte() & 128:
                return
        raise ValueError('unterminated heap type')
    if tag not in (0x7f, 0x7e, 0x7d, 0x7c, 0x7b, 0x70, 0x6f):
        raise ValueError('unsupported import value type')


def inspect(data):
    reader = Reader(data)
    if reader.take(8) != b'\0asm\1\0\0\0':
        raise ValueError('not a version-one module')
    imported, defined, seen = [], [], set()
    while reader.at < len(data):
        section = reader.byte()
        payload = Reader(reader.take(reader.uint()))
        if section not in (2, 5):
            continue
        if section in seen:
            raise ValueError('duplicate memory/import section')
        seen.add(section)
        count = payload.uint()
        if section == 5:
            defined = [limits(payload) for _ in range(count)]
        else:
            for _ in range(count):
                module, name, kind = payload.string(), payload.string(), payload.byte()
                if kind == 0:
                    payload.uint()
                elif kind == 1:
                    value_type(payload)
                    limits(payload, memory=False)
                elif kind == 2:
                    imported.append({'module': module, 'name': name, **limits(payload)})
                elif kind == 3:
                    value_type(payload)
                    if payload.byte() not in (0, 1):
                        raise ValueError('invalid global mutability')
                elif kind == 4:
                    if payload.byte() != 0:
                        raise ValueError('unsupported tag attribute')
                    payload.uint()
                else:
                    raise ValueError('unsupported import kind')
        payload.done()
    return {'imported': imported, 'defined': defined}


def same(before, after):
    a, b = inspect(before), inspect(after)
    if a != b:
        raise ValueError('MemoryBoundaryChanged')
    return a


def checks():
    header = b'\0asm\1\0\0\0'
    base = header + bytes([5, 4, 1, 1, 1, 3])
    expected = {'imported': [], 'defined': [{'minimum_pages': 1, 'maximum_pages': 3,
                                           'shared': False, 'address_bits': 32}]}
    assert inspect(base) == expected
    assert same(base, base) == expected
    names = ['literal_defined_min_max', 'identical_module']
    mutants = {
        'changed_minimum': [5, 4, 1, 1, 2, 3],
        'changed_maximum': [5, 4, 1, 1, 1, 4],
        'removed_maximum': [5, 3, 1, 0, 1],
        'changed_shared': [5, 4, 1, 3, 1, 3],
        'changed_address_width': [5, 4, 1, 5, 1, 3],
    }
    for name, payload in mutants.items():
        try:
            same(base, header + bytes(payload))
        except ValueError as error:
            assert str(error) == 'MemoryBoundaryChanged'
        else:
            raise AssertionError(name)
        names.append(name)
    imported = header + bytes([2, 9, 1, 1, 109, 1, 110, 2, 3, 1, 3])
    assert inspect(imported) == {'imported': [{'module': 'm', 'name': 'n',
        'minimum_pages': 1, 'maximum_pages': 3, 'shared': True, 'address_bits': 32}], 'defined': []}
    names.append('literal_imported_shared_memory')
    for name, changed in [('imported_name', imported.replace(b'n', b'x')),
                          ('imported_to_defined', base)]:
        try:
            same(imported, changed)
        except ValueError as error:
            assert str(error) == 'MemoryBoundaryChanged'
        else:
            raise AssertionError(name)
        names.append(name)
    for name, invalid in [('truncated_limits', base[:-1]),
                          ('unsupported_flags', header + bytes([5, 3, 1, 8, 1]))]:
        try:
            inspect(invalid)
        except ValueError:
            pass
        else:
            raise AssertionError(name)
        names.append(name)
    return names


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('before', type=Path, nargs='?')
    parser.add_argument('after', type=Path, nargs='?')
    parser.add_argument('--self-check', action='store_true')
    args = parser.parse_args()
    if args.self_check:
        print(json.dumps(checks(), indent=2))
        raise SystemExit(0)
    if args.before is None or args.after is None:
        parser.error('before and after are required')
    print(json.dumps({'checks': checks(), 'memory': same(args.before.read_bytes(), args.after.read_bytes()),
                      'sha256': {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in (args.before, args.after)}}, indent=2, sort_keys=True))
