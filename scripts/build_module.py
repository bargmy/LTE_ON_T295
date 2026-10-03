"""Build a Magisk ZIP with POSIX paths and Android permissions on any OS."""
from pathlib import Path
import stat
import zipfile

root = Path(__file__).resolve().parents[1]
properties = dict(
    line.split("=", 1) for line in (root / "module.prop").read_text().splitlines()
    if "=" in line and not line.startswith("#")
)
output = root / "dist" / f"{properties['id']}-{properties['version']}.zip"
output.parent.mkdir(exist_ok=True)
paths = [root / name for name in ("module.prop", "system.prop", "service.sh", "customize.sh")]
for directory in ("META-INF", "system"):
    paths.extend(p for p in (root / directory).rglob("*") if p.is_file())

with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(paths):
        name = path.relative_to(root).as_posix()
        data = path.read_bytes()
        if path.suffix in (".sh", ".prop", ".xml") or path.name in ("update-binary", "updater-script"):
            data = data.replace(b"\r\n", b"\n")
        executable = path.suffix == ".sh" or path.name == "update-binary" or "/bin/" in name
        info = zipfile.ZipInfo(name)
        info.create_system = 3
        info.external_attr = (stat.S_IFREG | (0o755 if executable else 0o644)) << 16
        archive.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED)
print(output)
