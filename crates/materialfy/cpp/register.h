#pragma once

namespace mf {

// Создать синглтоны и зарегистрировать типы Materialfy.Core 1.0. Вызывать после QApplication и
// crate::context::init(), до создания QQmlApplicationEngine.
void register_qml_types();

} // namespace mf
