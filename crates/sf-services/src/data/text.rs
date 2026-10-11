//! Подписи по-русски и разница списков для ListChange.
use md3_model::ListChange;

/// 1 трек, 2 трека, 5 треков.
pub fn plural(count: i64, one: &str, few: &str, many: &str) -> String {
    let n = count.unsigned_abs();
    let word = if n % 10 == 1 && n % 100 != 11 {
        one
    } else if (2..=4).contains(&(n % 10)) && !(12..=14).contains(&(n % 100)) {
        few
    } else {
        many
    };
    format!("{count} {word}")
}

pub fn tracks(count: i64) -> String {
    plural(count, "трек", "трека", "треков")
}

/// Как изменить `old`, чтобы получить `new`, не теряя прокрутку: дописывание, одна вставка, одно удаление
/// или перестановка одной строки; иначе — сброс. None — без изменений.
pub fn list_change<T: Clone + PartialEq>(old: &[T], new: &[T]) -> Option<ListChange<T>> {
    if old == new {
        return None;
    }
    if old.is_empty() {
        return Some(ListChange::Reset(new.to_vec()));
    }
    if new.len() > old.len() && new.starts_with(old) {
        return Some(ListChange::Append(new[old.len()..].to_vec()));
    }
    let prefix = old.iter().zip(new).take_while(|(a, b)| a == b).count();
    if new.len() > old.len() {
        let added = new.len() - old.len();
        if new[prefix + added..] == old[prefix..] {
            return Some(ListChange::Insert { at: prefix, items: new[prefix..prefix + added].to_vec() });
        }
    } else if new.len() < old.len() {
        let removed = old.len() - new.len();
        if old[prefix + removed..] == new[prefix..] {
            return Some(ListChange::Remove { at: prefix, count: removed });
        }
    } else {
        let suffix = old.iter().rev().zip(new.iter().rev()).take_while(|(a, b)| a == b).count();
        let end = old.len() - suffix;
        if end > prefix + 1 {
            let (from, to) = (prefix, end - 1);
            if old[from] == new[to] && old[from + 1..=to] == new[from..to] {
                return Some(ListChange::Move { from, to });
            }
            if old[to] == new[from] && old[from..to] == new[from + 1..=to] {
                return Some(ListChange::Move { from: to, to: from });
            }
        }
    }
    Some(ListChange::Reset(new.to_vec()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn russian_plurals() {
        assert_eq!(tracks(1), "1 трек");
        assert_eq!(tracks(3), "3 трека");
        assert_eq!(tracks(11), "11 треков");
        assert_eq!(tracks(22), "22 трека");
        assert_eq!(tracks(25), "25 треков");
    }

    #[test]
    fn small_edits_keep_rows() {
        assert_eq!(list_change(&[1, 2], &[1, 2]), None);
        assert_eq!(list_change(&[1, 2], &[1, 2, 3]), Some(ListChange::Append(vec![3])));
        assert_eq!(list_change(&[1, 2], &[0, 1, 2]), Some(ListChange::Insert { at: 0, items: vec![0] }));
        assert_eq!(list_change(&[1, 2, 3], &[1, 3]), Some(ListChange::Remove { at: 1, count: 1 }));
        assert_eq!(list_change(&[1, 2, 3, 4], &[2, 3, 1, 4]), Some(ListChange::Move { from: 0, to: 2 }));
        assert_eq!(list_change(&[1, 2, 3, 4], &[3, 1, 2, 4]), Some(ListChange::Move { from: 2, to: 0 }));
        assert_eq!(list_change(&[1, 2], &[3, 4]), Some(ListChange::Reset(vec![3, 4])));
    }
}
