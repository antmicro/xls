// Copyright 2023 The XLS Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <string>

#include "xls/dslx/create_import_data.h"
#include "xls/dslx/interp_value.h"
#include "xls/dslx/ir_convert/ir_converter.h"
#include "xls/dslx/parse_and_typecheck.h"
#include "xls/dslx/type_system/parametric_env.h"

int main() {
  const std::string program =
      "fn foo<WIDTH: u32>(val:bits[WIDTH]) -> bits[WIDTH] {"
      "  val + bits[WIDTH]:1"
      "}";

  auto options = xls::dslx::ConvertOptions{};
  auto import_data = xls::dslx::CreateImportDataForTest();

  auto checked_module_or = xls::dslx::ParseAndTypecheck(
      program, "test_module.x", "test_module", &import_data);

  if (!checked_module_or.ok()) {
    std::cerr << "Unable to parse and typecheck: " << checked_module_or.status()
              << std::endl;
    return 1;
  }
  const xls::dslx::TypecheckedModule& checked_module = checked_module_or.value();

  std::vector<std::pair<std::string, xls::dslx::InterpValue>> bindings = {
      {"WIDTH", xls::dslx::InterpValue::MakeU32(32)}};
  auto parametric_env = xls::dslx::ParametricEnv(bindings);

  auto ir_or = xls::dslx::ConvertOneFunction(
      /*module=*/checked_module.module,
      /*entry_function_name=*/"foo",
      /*import_data=*/&import_data,
      /*parametric_env=*/&parametric_env,
      /*options=*/options);

  if (!ir_or.ok()) {
    std::cout << "Unable to convert one function: " << ir_or.status() << std::endl;
    return 1;
  }

  return 0;
}
