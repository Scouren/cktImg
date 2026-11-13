#!/usr/bin/env python3
"""Fail-closed call-boundary guard around the vendored assembly comparison.

Usage: codegen_check.py <probe.s> gen=hand [gen=hand ...]
       codegen_check.py --self-test

Static instruction counts do not include callee bodies. Require identical
ordered direct call targets before accepting a pair, and reject external
tail jumps that could hide a wrapper's entire implementation. The semantic
consumer tests remain separate; this is not a functional-equivalence proof.
"""

import sys
from pathlib import Path

sys.dont_write_bytecode = True
import asm_probe


def calls(text, name):
    symbol = asm_probe.resolve(asm_probe.parse_aliases(text), name)
    body = asm_probe.body(text, symbol)
    if body is None:
        raise ValueError('missing probe symbol: ' + name)
    targets = []
    for code in body:
        mnemonic, operand = asm_probe.split(code)
        if mnemonic == 'jmp' and not operand.startswith('@'):
            raise ValueError('external tail hides a callee body: ' + name + ' -> ' + operand)
        if mnemonic == 'call':
            target = asm_probe.call_target(operand)
            if target is None:
                raise ValueError('indirect call cannot be compared: ' + name)
            targets.append(target)
    return targets


def guarded(text, generated, hand):
    a, b = calls(text, generated), calls(text, hand)
    if a != b:
        raise ValueError('different direct callees: ' + repr(a) + ' versus ' + repr(b))
    return asm_probe.probe(text, generated, hand)[0]


def self_test():
    asm_probe.self_test()
    def function(name, instructions):
        return name + ':\n' + '\n'.join(instructions) + '\n.size ' + name + ', 1\n'
    direct = function('hand', ['call identify', 'call portRole', 'ret'])
    assert guarded(direct + function('gen', ['call identify', 'call portRole', 'ret']), 'gen', 'hand') == 'IDENTICAL'
    assert guarded(direct + 'gen = hand\n', 'gen', 'hand') == 'FOLDED'
    residue = direct + function('gen', ['call identify', 'call portRole', 'add eax, 1', 'ret'])
    assert guarded(residue, 'gen', 'hand') == 'RESIDUE'
    for name, instructions in (
        ('full_role_hidden_by_small_wrapper', ['call identify', 'call role', 'ret']),
        ('wrapper_only_tail', ['jmp helper']),
        ('unknown_indirect_target', ['call rax', 'ret']),
        ('extra_same_callee_call', ['call identify', 'call portRole', 'call portRole', 'ret'])):
        try:
            guarded(direct + function('gen', instructions), 'gen', 'hand')
        except ValueError:
            continue
        raise AssertionError(name)
    print('codegen_check: call-boundary and residue mutations passed')


def main(argv):
    if argv[1:] == ['--self-test']:
        self_test()
        return 0
    if len(argv) < 3 or any('=' not in pair for pair in argv[2:]):
        print(__doc__, file=sys.stderr)
        return 2
    text = Path(argv[1]).read_text()
    for pair in argv[2:]:
        try:
            guarded(text, *pair.split('=', 1))
        except (ValueError, LookupError) as error:
            print('UNPROVED ' + pair + ': ' + str(error), file=sys.stderr)
            return 1
    return asm_probe.main(argv)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
