// Home — зеркало HomeService: полки главной ({key, title, kind, items:[…]}).
use std::pin::Pin;
use std::sync::Arc;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use sf_services::HomeSnapshot;

use super::{forward_watch, to_qlist};
use crate::context::ctx;
use crate::qt::QVariantList;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
    }

    unsafe extern "RustQt" {
        #[qobject]
        #[qproperty(QList_QVariant, shelves, READ, NOTIFY = changed)]
        #[qproperty(bool, loading, READ, NOTIFY = changed)]
        #[qproperty(QString, error_text, cxx_name = "errorText", READ, NOTIFY = changed)]
        type Home = super::HomeRust;

        #[qsignal]
        fn changed(self: Pin<&mut Home>);

        /// Обновить полки (force — без 10-минутного ограничения).
        #[qinvokable]
        fn refresh(self: &Home, force: bool);
    }

    impl cxx_qt::Threading for Home {}
    impl cxx_qt::Initialize for Home {}
}

#[derive(Default)]
pub struct HomeRust {
    snapshot: HomeSnapshot,
    shelves: QVariantList,
    loading: bool,
    error_text: QString,
}

impl qobject::Home {
    fn refresh(&self, force: bool) {
        ctx().services.home.refresh(force);
    }

    fn apply(mut self: Pin<&mut Self>, next: HomeSnapshot) {
        let prev = std::mem::replace(&mut self.as_mut().rust_mut().snapshot, next.clone());
        if prev == next {
            return;
        }
        let mut this = self.as_mut().rust_mut();
        if !Arc::ptr_eq(&prev.shelves, &next.shelves) {
            this.shelves = to_qlist(&next.shelves);
        }
        this.loading = next.loading;
        this.error_text = QString::from(next.error_text.as_str());
        self.changed();
    }
}

impl cxx_qt::Initialize for qobject::Home {
    fn initialize(mut self: Pin<&mut Self>) {
        let mut watch = ctx().services.home.watch();
        let snapshot = watch.borrow_and_update().clone();
        self.as_mut().apply(snapshot);
        forward_watch(self.qt_thread(), watch, Self::apply);
    }
}
