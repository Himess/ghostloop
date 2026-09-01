# Third-party notices

## Vesu v2

The ABI-compatible data shapes and method signatures in `src/interfaces.cairo`
are adapted from Vesu v2 at commit
[`2165e6c01bc4c6386d7cc57ece6d13b3d8a3560f`](https://github.com/vesuxyz/vesu-v2/tree/2165e6c01bc4c6386d7cc57ece6d13b3d8a3560f).

MIT License

Copyright (c) 2024 Vesu

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Vesu v2 periphery

The ABI-compatible Multiply parameter, action, response, route, and token
amount shapes in `src/interfaces.cairo` are adapted from Vesu v2 periphery at
commit
[`3aa1b95af0663cd1fc575cef31ded88816e67277`](https://github.com/vesuxyz/vesu-v2-periphery/tree/3aa1b95af0663cd1fc575cef31ded88816e67277).
That upstream repository is distributed under the Business Source License
1.1; see its pinned [`LICENSE`](https://github.com/vesuxyz/vesu-v2-periphery/blob/3aa1b95af0663cd1fc575cef31ded88816e67277/LICENSE).
No Multiply, swap, callback, or Ekubo execution implementation is vendored.

The `PoolKey` and `i129` field layouts were independently checked against the
canonical deployed Multiply V2 class ABI at Mainnet block `4172487`.

## Starknet Privacy

The ABI-compatible `OpenNoteDeposit` structure in `src/interfaces.cairo` is
adapted from
[`starkware-libs/starknet-privacy`](https://github.com/starkware-libs/starknet-privacy/blob/4db755b9512f00b540126737b605472ea2275e15/packages/privacy/src/objects.cairo),
licensed under Apache License 2.0. No privacy-pool implementation is vendored.

Copyright 2025 StarkWare Industries Ltd.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy of the
License at <https://www.apache.org/licenses/LICENSE-2.0>.

Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.
