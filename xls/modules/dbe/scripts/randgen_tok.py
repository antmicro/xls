#!/usr/bin/env python3

# Copyright 2023 The XLS Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


import random
from dbe import prettify, get_random_tokens, Params, Decoder


SYM_BITS = 4
PTR_BITS = 3
CNT_BITS = 4

OFSSLOPE = 2
CNTSLOPE = 4
NTOKS = 32
NPERLINE = 16


random.seed(0)

cfg = Params(SYM_BITS, PTR_BITS, CNT_BITS)
toks = get_random_tokens(NTOKS, cfg, OFSSLOPE, CNTSLOPE)
d = Decoder(cfg)
for t in toks:
    d.feed(t)

print(f'Tokens (len={len(d.toks)}):')
print(',\n'.join(repr(t) for t in d.toks))
print('')
print(f'DSLX array (len={len(d.toks)}):')
print(',\n'.join(t.to_dslx(cfg) for t in d.toks))
print('')
print(f'Reference decoding (len={len(d.out)}):')
print(prettify((f'{x:2d}' for x in d.out), NPERLINE))
print('')
print('Done.')
