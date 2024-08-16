# Copyright 2024 The XLS Authors
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

from xls.modules.zstd.cocotb.xlsstruct import xls_dataclass, XLSStruct

DATA_WIDTH = 32
ID_WIDTH = 4
DEST_WIDTH = 4

@xls_dataclass
class AxiStreamStruct(XLSStruct):
  data: DATA_WIDTH
  str: DATA_WIDTH // 8
  keep: DATA_WIDTH // 8 = 0
  last: 1 = 0
  id: ID_WIDTH = 0
  dest: DEST_WIDTH = 0


ADDR_WIDTH = 16

@xls_dataclass
class TransferDescStruct(XLSStruct):
  address: ADDR_WIDTH
  length: ADDR_WIDTH


@xls_dataclass
class EmptyStruct(XLSStruct):
  pass
