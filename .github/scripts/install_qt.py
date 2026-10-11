#!/usr/bin/env python3
"""Ставит Qt из онлайн-репозитория download.qt.io без установщика и без aqtinstall.

aqtinstall 3.3 не разбирает новую раскладку репозитория Qt 6.12 (qt6_6120/qt6_6120_<arch>),
поэтому читаем Updates.xml сами: берём пакет qt.qt6.<ver>.<arch> и нужные addons, качаем все их
DownloadableArchives, сверяем SHA-1 и распаковываем 7z в один префикс. Архивы Qt 6 перемещаемые —
qt.conf и правка путей не нужны.

    python3 install_qt.py --out ~/Qt/6.12.0/gcc_64 --addons qtshadertools qtimageformats

В stdout — только путь к qmake (журнал — в stderr). --github дописывает QTDIR/QMAKE в $GITHUB_ENV и bin в $GITHUB_PATH. Если в --out уже стоит тот же
набор пакетов (метка .materialfy-qt), ничего не качает — так работает кэш CI.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

BASE = "https://download.qt.io/online/qtsdkrepository"
MARKER = ".materialfy-qt"

# хост → (каталог ОС в репозитории, архитектура по умолчанию, суффикс имени пакета)
HOSTS = {
    "windows": ("windows_x86", "msvc2022_64", "win64_msvc2022_64"),
    "linux": ("linux_x64", "linux_gcc_64", "linux_gcc_64"),
    "linux_arm64": ("linux_arm64", "linux_gcc_arm64", "linux_gcc_arm64"),
    "mac": ("mac_x64", "clang_64", "clang_64"),
}


def log(msg: str) -> None:
    print(f"[install_qt] {msg}", file=sys.stderr, flush=True)


def fetch(url: str, dest: Path | None = None, attempts: int = 4) -> bytes:
    for i in range(1, attempts + 1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "materialfy-ci"})
            with urllib.request.urlopen(req, timeout=120) as resp:
                if dest is None:
                    return resp.read()
                with open(dest, "wb") as f:
                    shutil.copyfileobj(resp, f, 1 << 20)
                return b""
        except urllib.error.HTTPError as e:
            if e.code == 404:
                raise
            err = e
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            err = e
        log(f"сбой {url}: {err}; попытка {i}/{attempts}")
        time.sleep(3 * i)
    raise RuntimeError(f"не удалось скачать {url}")


def repo_candidates(os_dir: str, ver: str, arch: str) -> list[str]:
    tag = f"qt6_{ver.replace('.', '')}"
    # 6.8+: qt6_6120/qt6_6120_<arch> (Windows) или qt6_6120/qt6_6120 (Linux, macOS); старые — плоско
    return [
        f"{BASE}/{os_dir}/desktop/{tag}/{tag}_{arch}",
        f"{BASE}/{os_dir}/desktop/{tag}/{tag}",
        f"{BASE}/{os_dir}/desktop/{tag}",
    ]


def load_repo(os_dir: str, ver: str, arch: str) -> tuple[str, ET.Element]:
    for url in repo_candidates(os_dir, ver, arch):
        try:
            data = fetch(f"{url}/Updates.xml")
        except urllib.error.HTTPError:
            continue
        log(f"репозиторий: {url}")
        return url, ET.fromstring(data)
    raise SystemExit(f"Updates.xml для Qt {ver} ({os_dir}, {arch}) не найден")


def find_7z() -> str:
    for name in ("7z", "7zz", "7za"):
        exe = shutil.which(name)
        if exe:
            return exe
    for path in (r"C:\Program Files\7-Zip\7z.exe", "/opt/homebrew/bin/7zz", "/usr/local/bin/7zz"):
        if Path(path).exists():
            return path
    raise SystemExit("нужен 7-Zip: 7z (Windows, p7zip-full) или 7zz (brew install sevenzip)")


def sha1_of(path: Path) -> str:
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    # консоль Windows — cp1251/cp866, а сообщения по-русски
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    host_default = {"Windows": "windows", "Darwin": "mac"}.get(platform.system(), "linux")
    if host_default == "linux" and platform.machine() in ("aarch64", "arm64"):
        host_default = "linux_arm64"
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", choices=HOSTS, default=host_default)
    ap.add_argument("--version", default="6.12.0")
    ap.add_argument("--arch", help="каталог в репозитории (msvc2022_64, linux_gcc_64, linux_gcc_arm64, clang_64)")
    ap.add_argument("--addons", nargs="*", default=["qtshadertools", "qtimageformats"])
    ap.add_argument("--out", required=True, type=Path, help="префикс Qt (будет содержать bin/, lib/, qml/ …)")
    ap.add_argument("--skip", nargs="*", default=["qtdoc"], help="префиксы архивов, которые не нужны")
    ap.add_argument("--github", action="store_true", help="экспортировать QTDIR/QMAKE/PATH для GitHub Actions")
    ap.add_argument("--dry-run", action="store_true", help="только показать архивы")
    args = ap.parse_args()

    os_dir, arch_default, _ = HOSTS[args.host]
    arch = args.arch or arch_default
    suffix = HOSTS[args.host][2] if arch == arch_default else (f"win64_{arch}" if args.host == "windows" else arch)
    vtag = args.version.replace(".", "")
    names = [f"qt.qt6.{vtag}.{suffix}"] + [f"qt.qt6.{vtag}.addons.{a}.{suffix}" for a in args.addons]

    out: Path = args.out.expanduser().resolve()
    stamp = "\n".join([args.version, arch, *names, *sorted(args.skip)])
    marker = out / MARKER
    qmake = out / "bin" / ("qmake6.exe" if args.host == "windows" else "qmake6")
    if not qmake.exists():
        qmake = qmake.with_name("qmake.exe" if args.host == "windows" else "qmake")

    if marker.exists() and marker.read_text(encoding="utf-8") == stamp and qmake.exists():
        log(f"Qt уже стоит в {out}")
    else:
        repo, root = load_repo(os_dir, args.version, arch)
        packages = {p.findtext("Name"): p for p in root.findall("PackageUpdate")}
        jobs: list[tuple[str, str]] = []
        for name in names:
            pkg = packages.get(name)
            if pkg is None:
                raise SystemExit(f"в репозитории нет пакета {name}")
            version = pkg.findtext("Version") or ""
            archives = [a.strip() for a in (pkg.findtext("DownloadableArchives") or "").split(",") if a.strip()]
            for archive in archives:
                if any(archive.startswith(s) for s in args.skip):
                    continue
                jobs.append((archive, f"{repo}/{name}/{version}{archive}"))
        for archive, url in jobs:
            log(f"{archive} <- {url}")
        if args.dry_run:
            return 0

        seven = find_7z()
        if out.exists():
            shutil.rmtree(out)
        out.mkdir(parents=True)
        with tempfile.TemporaryDirectory(prefix="qt-dl-") as tmp:
            for archive, url in jobs:
                dest = Path(tmp) / archive
                fetch(url, dest)
                expected = fetch(f"{url}.sha1").decode().split()[0].strip().lower()
                actual = sha1_of(dest)
                if actual != expected:
                    raise SystemExit(f"SHA-1 не совпал для {archive}: {actual} != {expected}")
                cmd = [seven, "x", "-y", "-bd", "-bso0", f"-o{out}", str(dest)]
                # 7-Zip отбрасывает симлинки архивов Qt (libQt6*.so -> .so.6) как «опасные»:
                # 25.x пропускает их с -snld20, 21–24 — с -snld, старый p7zip 16.02 ключей не знает
                for flags in (["-snld20"], ["-snld"], []):
                    if subprocess.run([*cmd, *flags]).returncode == 0:
                        break
                else:
                    raise SystemExit(f"7z не распаковал {archive}")
                dest.unlink()
                log(f"распакован {archive}")
        # архив ICU (Linux) ложится в корень, а Qt ищет его через RUNPATH $ORIGIN/../lib
        for icu in out.glob("libicu*.so*"):
            shutil.move(str(icu), out / "lib" / icu.name)
        if not qmake.exists():
            qmake = qmake.with_name("qmake.exe" if args.host == "windows" else "qmake")
        if not qmake.exists():
            raise SystemExit(f"после распаковки нет {qmake}")
        marker.write_text(stamp, encoding="utf-8")
        log(f"Qt {args.version} установлен в {out}")

    if args.github:
        with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as f:
            f.write(f"QTDIR={out}\nQMAKE={qmake}\nQt6_DIR={out}\n")
        with open(os.environ["GITHUB_PATH"], "a", encoding="utf-8") as f:
            f.write(f"{out / 'bin'}\n")
    print(qmake)
    return 0


if __name__ == "__main__":
    sys.exit(main())
