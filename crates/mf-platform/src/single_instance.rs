//! Единственный экземпляр (app.py: raise_running_instance).
//! Linux: если на сессионной шине уже есть mpris::BUS_NAME — вызвать у него org.mpris.MediaPlayer2.Raise
//! и вернуть true (вызывающий выходит с кодом 0). Работающий экземпляр получает просьбу как MprisCommand::Raise.
//!
//! Windows и macOS (дополнение к Python-версии, где там всегда false): работающий экземпляр держит
//! [`InstanceListener`] — именованный канал `\\.\pipe\materialfy-Materialfy-<user>` (создаётся как первый экземпляр
//! канала, т. е. работает и как мьютекс) или unix-сокет `$TMPDIR/materialfy-Materialfy.sock`. Новый процесс подключается,
//! пишет "raise\n" и выходит; без слушателя (оболочка его не запустила) — false, как раньше.
//! Протокол: клиент — строка "raise\n", сервер — ответ "ok\n".
use std::time::Duration;

use tokio::sync::mpsc;

use crate::PlatformError;

#[cfg(any(target_os = "windows", target_os = "macos"))]
const REQUEST: &[u8] = b"raise\n";
#[cfg(any(target_os = "windows", target_os = "macos"))]
const REPLY: &[u8] = b"ok\n";
const TIMEOUT: Duration = Duration::from_secs(3);

/// true — работающий экземпляр найден и попрошен показать окно.
pub async fn raise_running_instance() -> bool {
    match tokio::time::timeout(TIMEOUT, imp::raise()).await {
        Ok(found) => found,
        Err(_) => {
            tracing::debug!("the running instance did not answer in time");
            false
        }
    }
}

/// Слушатель просьб «показать окно» от новых процессов (Windows/macOS).
/// На Linux не нужен: `start` возвращает Err(Unsupported), просьба приходит через MPRIS.
pub struct InstanceListener {
    requests: mpsc::UnboundedReceiver<()>,
    task: tokio::task::JoinHandle<()>,
}

impl InstanceListener {
    /// Занять канал/сокет. Ошибка — другой экземпляр уже слушает (или ОС не поддерживается).
    /// Вызывать внутри tokio-рантайма.
    pub async fn start() -> Result<InstanceListener, PlatformError> {
        let (tx, requests) = mpsc::unbounded_channel();
        let task = imp::listen(tx).await?;
        Ok(InstanceListener { requests, task })
    }

    /// Ждать следующей просьбы показать окно; None — слушатель остановлен.
    pub async fn recv(&mut self) -> Option<()> {
        self.requests.recv().await
    }

    /// Отдать канал просьб (слушатель продолжает работать, пока жив рантайм).
    pub fn into_receiver(self) -> mpsc::UnboundedReceiver<()> {
        self.requests
    }

    pub fn close(self) {
        self.task.abort();
    }
}

/// Обработать одно подключение: прочитать просьбу, ответить.
#[cfg(any(target_os = "windows", target_os = "macos"))]
async fn serve_client<S>(mut stream: S, tx: mpsc::UnboundedSender<()>)
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin,
{
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let mut buf = [0u8; 16];
    let mut len = 0;
    let read = tokio::time::timeout(TIMEOUT, async {
        while len < buf.len() {
            match stream.read(&mut buf[len..]).await {
                Ok(0) | Err(_) => break,
                Ok(n) => len += n,
            }
            if buf[..len].contains(&b'\n') {
                break;
            }
        }
    });
    let _ = read.await;
    if buf[..len] == *REQUEST {
        let _ = tx.send(());
        let _ = stream.write_all(REPLY).await;
        let _ = stream.flush().await;
    }
}

/// Клиент: отправить просьбу и дождаться ответа. true — запрос доставлен.
#[cfg(any(target_os = "windows", target_os = "macos"))]
async fn send_request<S>(mut stream: S) -> bool
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin,
{
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    if stream.write_all(REQUEST).await.is_err() || stream.flush().await.is_err() {
        return false;
    }
    let mut reply = [0u8; 8];
    match stream.read(&mut reply).await {
        Ok(n) if reply[..n] == *REPLY => true,
        // запрос ушёл, даже если ответ не дошёл — второй экземпляр всё равно не нужен
        _ => true,
    }
}

#[cfg(target_os = "linux")]
mod imp {
    use tokio::sync::mpsc;
    use tokio::task::JoinHandle;

    use crate::PlatformError;
    use crate::mpris::{BUS_NAME, OBJECT_PATH};

    pub async fn raise() -> bool {
        match try_raise().await {
            Ok(found) => found,
            Err(err) => {
                tracing::debug!("D-Bus unavailable: {err}");
                false
            }
        }
    }

    async fn try_raise() -> zbus::Result<bool> {
        let conn = zbus::Connection::session().await?;
        let dbus = zbus::fdo::DBusProxy::new(&conn).await?;
        let name = zbus::names::BusName::try_from(BUS_NAME)?;
        if !dbus.name_has_owner(name).await? {
            return Ok(false);
        }
        let reply = conn
            .call_method(Some(BUS_NAME), OBJECT_PATH, Some("org.mpris.MediaPlayer2"), "Raise", &())
            .await;
        Ok(reply.is_ok())
    }

    pub async fn listen(_tx: mpsc::UnboundedSender<()>) -> Result<JoinHandle<()>, PlatformError> {
        Err(PlatformError::Unsupported)
    }
}

#[cfg(target_os = "windows")]
mod imp {
    use std::os::windows::io::AsRawHandle;
    use std::time::Duration;

    use tokio::net::windows::named_pipe::{ClientOptions, NamedPipeServer, ServerOptions};
    use tokio::sync::mpsc;
    use tokio::task::JoinHandle;

    use crate::PlatformError;
    use crate::dirs::{APPLICATION, ORGANIZATION};

    const ERROR_PIPE_BUSY: i32 = 231;

    pub fn pipe_name() -> String {
        let user: String = std::env::var("USERNAME")
            .unwrap_or_default()
            .chars()
            .map(|c| if c.is_alphanumeric() || c == '-' || c == '_' { c } else { '_' })
            .collect();
        format!(r"\\.\pipe\{ORGANIZATION}-{APPLICATION}-{user}")
    }

    pub async fn raise() -> bool {
        let name = pipe_name();
        let mut attempts = 0;
        let client = loop {
            match ClientOptions::new().open(&name) {
                Ok(client) => break client,
                Err(err) if err.raw_os_error() == Some(ERROR_PIPE_BUSY) && attempts < 20 => {
                    attempts += 1;
                    tokio::time::sleep(Duration::from_millis(50)).await;
                }
                Err(_) => return false,
            }
        };
        allow_foreground(&client);
        super::send_request(client).await
    }

    /// Разрешить работающему экземпляру вывести окно на передний план (иначе Windows только мигнёт кнопкой).
    fn allow_foreground(client: &impl AsRawHandle) {
        use windows_sys::Win32::System::Pipes::GetNamedPipeServerProcessId;
        use windows_sys::Win32::UI::WindowsAndMessaging::AllowSetForegroundWindow;
        let mut pid = 0u32;
        // SAFETY: дескриптор открытого канала живёт дольше вызова, pid — валидный указатель
        unsafe {
            if GetNamedPipeServerProcessId(client.as_raw_handle(), &mut pid) != 0 && pid != 0 {
                AllowSetForegroundWindow(pid);
            }
        }
    }

    fn create(name: &str, first: bool) -> std::io::Result<NamedPipeServer> {
        ServerOptions::new().first_pipe_instance(first).create(name)
    }

    pub async fn listen(tx: mpsc::UnboundedSender<()>) -> Result<JoinHandle<()>, PlatformError> {
        let name = pipe_name();
        let mut server = create(&name, true)?;
        Ok(tokio::spawn(async move {
            loop {
                if let Err(err) = server.connect().await {
                    tracing::debug!("single-instance channel: {err}");
                }
                let next = match create(&name, false) {
                    Ok(next) => next,
                    Err(err) => {
                        tracing::warn!("single-instance channel closed: {err}");
                        return;
                    }
                };
                let client = std::mem::replace(&mut server, next);
                tokio::spawn(super::serve_client(client, tx.clone()));
            }
        }))
    }
}

#[cfg(target_os = "macos")]
mod imp {
    use std::path::PathBuf;

    use tokio::net::{UnixListener, UnixStream};
    use tokio::sync::mpsc;
    use tokio::task::JoinHandle;

    use crate::PlatformError;
    use crate::dirs::{APPLICATION, ORGANIZATION};

    pub fn socket_path() -> PathBuf {
        // $TMPDIR на macOS — свой у каждого пользователя
        std::env::temp_dir().join(format!("{ORGANIZATION}-{APPLICATION}.sock"))
    }

    pub async fn raise() -> bool {
        match UnixStream::connect(socket_path()).await {
            Ok(stream) => super::send_request(stream).await,
            Err(_) => false,
        }
    }

    pub async fn listen(tx: mpsc::UnboundedSender<()>) -> Result<JoinHandle<()>, PlatformError> {
        let path = socket_path();
        if UnixStream::connect(&path).await.is_ok() {
            return Err(std::io::Error::from(std::io::ErrorKind::AddrInUse).into());
        }
        // сокет от упавшего процесса
        let _ = std::fs::remove_file(&path);
        let listener = UnixListener::bind(&path)?;
        Ok(tokio::spawn(async move {
            loop {
                match listener.accept().await {
                    Ok((stream, _)) => {
                        tokio::spawn(super::serve_client(stream, tx.clone()));
                    }
                    Err(err) => {
                        tracing::warn!("single-instance socket closed: {err}");
                        return;
                    }
                }
            }
        }))
    }
}

#[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
mod imp {
    use tokio::sync::mpsc;
    use tokio::task::JoinHandle;

    use crate::PlatformError;

    pub async fn raise() -> bool {
        false
    }

    pub async fn listen(_tx: mpsc::UnboundedSender<()>) -> Result<JoinHandle<()>, PlatformError> {
        Err(PlatformError::Unsupported)
    }
}

#[cfg(test)]
mod tests {
    #[cfg(any(target_os = "windows", target_os = "macos"))]
    #[tokio::test]
    async fn protocol_roundtrip() {
        let (client, server) = tokio::io::duplex(64);
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        let served = tokio::spawn(super::serve_client(server, tx));
        assert!(super::send_request(client).await);
        served.await.unwrap();
        assert_eq!(rx.recv().await, Some(()));
    }

    #[cfg(any(target_os = "windows", target_os = "macos"))]
    #[tokio::test]
    async fn garbage_is_ignored() {
        use tokio::io::AsyncWriteExt;
        let (mut client, server) = tokio::io::duplex(64);
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        let served = tokio::spawn(super::serve_client(server, tx));
        client.write_all(b"hello\n").await.unwrap();
        served.await.unwrap();
        assert!(rx.try_recv().is_err());
    }

    /// Настоящий канал/сокет: занимает имя пользователя, поэтому не по умолчанию.
    #[cfg(any(target_os = "windows", target_os = "macos"))]
    #[tokio::test]
    #[ignore = "takes the single-instance name"]
    async fn listener_receives_raise() {
        let mut listener = super::InstanceListener::start().await.unwrap();
        assert!(super::InstanceListener::start().await.is_err());
        assert!(super::raise_running_instance().await);
        assert_eq!(listener.recv().await, Some(()));
        listener.close();
    }
}
