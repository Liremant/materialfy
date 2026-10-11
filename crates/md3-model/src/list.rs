/// Изменение списка — мост применяет его к DictListModel (begin/endInsertRows и т. д.).
#[derive(Clone, Debug, PartialEq)]
pub enum ListChange<T> {
    Reset(Vec<T>),
    Append(Vec<T>),
    Insert { at: usize, items: Vec<T> },
    Remove { at: usize, count: usize },
    /// перестановка одной строки (редактирование плейлиста, очередь)
    Move { from: usize, to: usize },
    Loading(bool),
}
