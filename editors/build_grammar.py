#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# Copyright © 2026 Connor Rutberg
#
# editors/build_grammar.py - generates the Strata TextMate grammar used by BOTH editors:
#     editors/vscode/syntaxes/strata.tmLanguage.json
# (Visual Studio's installer copies that same file.) Regexes live here as Python raw
# strings, so there is no hand-escaping of JSON. Re-run after changing the language:
#
#     python editors/build_grammar.py
#
# Keep the word lists in sync with compiler/src/lexer.strata (keywords) and
# compiler/src/checker.strata (primitive types, built-in functions).

import json, os

KEYWORDS_CONTROL = ['if', 'else', 'while', 'for', 'in', 'return', 'break', 'continue', 'switch', 'case', 'default']
KEYWORDS_MEMORY  = ['region']
KEYWORDS_OPS     = ['cast', 'sizeof']
STORAGE          = ['var', 'const', 'struct', 'enum', 'export', 'global', 'foreign']   # global / foreign: contextual (top level)
CONSTANTS        = ['true', 'false', 'null']
PRIM_TYPES = ['int', 'uint', 'i8', 'i16', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64',
              'float', 'f32', 'f64', 'bool', 'char', 'string', 'void',
              'vec2', 'vec3', 'vec4', 'mat4', 'quat', 'Arena']
BUILTINS = ['print', 'arena', 'alloc', 'args', 'substr', 'int_to_str', 'read_file',
            'write_file', 'cstr', 'min', 'max', 'clamp', 'lerp', 'dot', 'cross', 'length',
            'normalize', 'mat4_identity', 'mat4_translate', 'mat4_scale', 'mat4_rotate',
            'mat4_perspective', 'mat4_look_at', 'quat_identity', 'quat_axis_angle',
            'quat_rotate', 'quat_to_mat4', 'quat_normalize']
BUILTIN_CONSTS = ['PI']
METHODS = ['new', 'push', 'len']

def words(ws): return r'\b(' + '|'.join(ws) + r')\b'

IDENT = r'[A-Za-z_][A-Za-z0-9_]*'
# the second word of `Type name` must not be a keyword (`for x in xs`, `a else ...`)
NOT_KW = r'(?!(?:in|else|return|case|default)\b)'
# a type suffix run: `*`, `[]`, `[64]`, `[dynamic]`
# The `*` must touch the name (`Node* next`), which is how pointer types are written;
# a spaced `*` is multiplication (`e.vel * dt`).
SUFFIX = r'(?:\*|\[\s*(?:[0-9]+|dynamic)?\s*\])*'

grammar = {
    '$schema': 'https://raw.githubusercontent.com/martinring/tmlanguage/master/tmlanguage.json',
    'name': 'Strata',
    'scopeName': 'source.strata',
    'fileTypes': ['strata', 'str'],   # Visual Studio uses this; VS Code uses package.json
    'patterns': [
        {'include': '#comments'},
        {'include': '#imports'},
        {'include': '#strings'},
        {'include': '#chars'},
        {'include': '#numbers'},
        {'include': '#decl-names'},
        {'include': '#cast'},
        {'include': '#type-args'},
        {'include': '#keywords'},
        {'include': '#constants'},
        {'include': '#types'},
        {'include': '#builtins'},
        {'include': '#user-types'},
        {'include': '#members'},
        {'include': '#functions'},
        {'include': '#operators'},
    ],
    'repository': {
        'comments': {'patterns': [
            {'name': 'comment.line.double-slash.strata', 'match': r'//.*$'},
            {'include': '#block-comment'},
        ]},
        # block comments NEST in Strata (see lexer.strata skip_trivia)
        'block-comment': {
            'name': 'comment.block.strata',
            'begin': r'/\*', 'end': r'\*/',
            'patterns': [{'include': '#block-comment'}],
        },
        'imports': {'patterns': [
            {   # import <raylib.h> / import "foo.h"  (C headers)
                'match': r'^\s*(import)\s+(<[^>]*>|"[^"]*")',
                'captures': {'1': {'name': 'keyword.control.import.strata'},
                             '2': {'name': 'string.quoted.other.include.strata'}},
            },
            {   # import gfx.Renderer  (Strata modules)
                'match': r'^\s*(import)\s+([A-Za-z_][\w.]*)',
                'captures': {'1': {'name': 'keyword.control.import.strata'},
                             '2': {'name': 'entity.name.namespace.strata'}},
            },
            {   # link "raylib"
                'match': r'^\s*(link)\s+("[^"]*")',
                'captures': {'1': {'name': 'keyword.control.import.strata'},
                             '2': {'name': 'string.quoted.double.strata'}},
            },
        ]},
        'strings': {
            'name': 'string.quoted.double.strata',
            'begin': '"', 'end': '"',
            'patterns': [
                {'name': 'constant.character.escape.strata', 'match': r'\\[ntr0\\"]'},
                {'name': 'invalid.illegal.escape.strata', 'match': r'\\.'},
            ],
        },
        'chars': {'patterns': [
            {'name': 'string.quoted.single.strata', 'match': r"'(\\[ntr0\\'])'",
             'captures': {'1': {'name': 'constant.character.escape.strata'}}},
            {'name': 'string.quoted.single.strata', 'match': r"'[^'\\]'"},
        ]},
        'numbers': {'patterns': [
            {'name': 'constant.numeric.hex.strata', 'match': r'\b0[xX][0-9a-fA-F_]+\b'},
            {'name': 'constant.numeric.binary.strata', 'match': r'\b0[bB][01_]+\b'},
            # `1.5` / `1e9` are floats; `0..10` is two ints and a range (needs a digit after `.`)
            {'name': 'constant.numeric.float.strata',
             'match': r'\b[0-9][0-9_]*(?:\.[0-9][0-9_]*(?:[eE][+-]?[0-9]+)?|[eE][+-]?[0-9]+)\b'},
            {'name': 'constant.numeric.integer.strata', 'match': r'\b[0-9][0-9_]*\b'},
        ]},
        # struct Name / enum Name
        'decl-names': {
            'match': r'\b(struct|enum)\s+(' + IDENT + r')',
            'captures': {'1': {'name': 'storage.type.strata'},
                         '2': {'name': 'entity.name.type.strata'}},
        },
        # cast<T>(x)
        'cast': {
            'begin': r'\b(cast)\s*(<)', 'end': r'>',
            'beginCaptures': {'1': {'name': 'keyword.operator.cast.strata'},
                              '2': {'name': 'punctuation.definition.typeparameters.begin.strata'}},
            'endCaptures': {'0': {'name': 'punctuation.definition.typeparameters.end.strata'}},
            'patterns': [{'include': '#types'}, {'include': '#type-name'},
                         {'include': '#operators'}],
        },
        # sizeof(T) / arena.new(T): the argument is a type
        'type-args': {'patterns': [
            {'begin': r'\b(sizeof)\s*(\()', 'end': r'\)',
             'beginCaptures': {'1': {'name': 'keyword.operator.sizeof.strata'}},
             'patterns': [{'include': '#types'}, {'include': '#type-name'},
                          {'include': '#operators'}]},
            {'match': r'(?<=\.)(new)\s*\(\s*(' + IDENT + r')',
             'captures': {'1': {'name': 'support.function.method.strata'},
                          '2': {'patterns': [{'include': '#types'}, {'include': '#type-name'}]}}},
        ]},
        'keywords': {'patterns': [
            {'name': 'keyword.control.strata', 'match': words(KEYWORDS_CONTROL)},
            {'name': 'keyword.other.region.strata', 'match': words(KEYWORDS_MEMORY)},
            {'name': 'keyword.operator.sizeof.strata', 'match': words(KEYWORDS_OPS)},
            {'name': 'storage.modifier.strata', 'match': words(STORAGE)},
            {'name': 'storage.modifier.dynamic.strata', 'match': r'(?<=\[)\s*dynamic\b'},
        ]},
        'constants': {'patterns': [
            {'name': 'constant.language.strata', 'match': words(CONSTANTS)},
            {'name': 'support.constant.strata', 'match': words(BUILTIN_CONSTS)},
        ]},
        'types': {'name': 'storage.type.strata', 'match': words(PRIM_TYPES)},
        'builtins': {
            'match': words(BUILTINS) + r'(?=\s*\()',
            'captures': {'1': {'name': 'support.function.builtin.strata'}},
        },
        'type-name': {'name': 'entity.name.type.strata', 'match': IDENT},
        # a user type in declaration position: `Entity e`, `Node* next`, `Ball[dynamic] bs`
        # (a name, then optional */[] suffixes, then another name), or a struct literal
        # `Entity{ ... }`.
        'user-types': {'patterns': [
            {'match': r'\b(' + IDENT + r')(?=' + SUFFIX + r'\s+' + NOT_KW + IDENT + r')',
             'captures': {'1': {'name': 'entity.name.type.strata'}}},
            # a suffixed type closing a list: `sizeof(Pair*)`, `cast<u8*>`, `f(Node*, int)`
            {'match': r'\b(' + IDENT + r')(?=(?:\*|\[\s*(?:[0-9]+|dynamic)?\s*\])+\s*[)>,])',
             'captures': {'1': {'name': 'entity.name.type.strata'}}},
            {'match': r'\b([A-Z][A-Za-z0-9_]*)(?=\s*\{)',
             'captures': {'1': {'name': 'entity.name.type.strata'}}},
        ]},
        'functions': {
            'match': r'\b(' + IDENT + r')(?=\s*\()',
            'captures': {'1': {'name': 'entity.name.function.strata'}},
        },
        # .push / .new / .len
        'members': {
            'match': r'(?<=\.)' + words(METHODS),
            'captures': {'1': {'name': 'support.function.method.strata'}},
        },
        'operators': {'patterns': [
            {'name': 'keyword.operator.range.strata', 'match': r'\.\.'},
            {'name': 'keyword.operator.strata',
             'match': r'<<=|>>=|&&|\|\||==|!=|<=|>=|\+=|-=|\*=|/=|\|=|&=|\^=|<<|>>|[-+*/%<>=!&|^~]'},
        ]},
    },
}

here = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(here, 'vscode', 'syntaxes', 'strata.tmLanguage.json')
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, 'w', encoding='utf-8', newline='\n') as f:
    json.dump(grammar, f, indent=2, ensure_ascii=False)
    f.write('\n')
print('wrote', os.path.relpath(out, os.path.dirname(here)))
