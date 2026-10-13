#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
task_work=${OPENCOMMANDER_BUILD_ROOT:-"$task_root/build"}
task_dist=${OPENCOMMANDER_DIST_ROOT:-"$task_root/dist"}
task_artifacts=${OPENCOMMANDER_ARTIFACT_ROOT:-"$task_root/artifacts"}
if [ ! -x "$task_root/.venv/bin/python" ]; then
    python3 -m venv "$task_root/.venv"
fi
"$task_root/.venv/bin/python" -m pip install --no-cache-dir -r "$task_root/requirements-dev.txt"
mkdir -p "$task_work" "$task_dist" "$task_artifacts"
# Qt 6's X11 platform plugin needs this small Ubuntu runtime library.
# Download/extract it locally; never install a system package or request root.
task_runtime="$task_work/xcb-runtime"
mkdir -p "$task_runtime"
(cd "$task_runtime" && apt-get download libxcb-cursor0)
for task_deb in "$task_runtime"/libxcb-cursor0_*.deb; do
    dpkg-deb -x "$task_deb" "$task_runtime/root"
done
task_cursor=$("$task_root/.venv/bin/python" -c 'import glob,sys; print(glob.glob(sys.argv[1]+"/root/usr/lib/*/libxcb-cursor.so.0")[0])' "$task_runtime")
task_archive=$("$task_root/.venv/bin/python" -c 'import glob; print(glob.glob("/lib/*/libarchive.so.13")[0])')
set --
if [ -n "${OPENCOMMANDER_GOOGLE_OAUTH_FILE:-}" ]; then
    task_oauth="$task_work/public-oauth/google-oauth.json"
    PYTHONPATH="$task_root" "$task_root/.venv/bin/python" -m opencommander.public_oauth \
        "$OPENCOMMANDER_GOOGLE_OAUTH_FILE" "$task_oauth"
    set -- --add-data "$task_oauth:opencommander/assets"
fi
for task_provider in onedrive dropbox; do
    case "$task_provider" in
        onedrive) task_source=${OPENCOMMANDER_ONEDRIVE_OAUTH_FILE:-} ;;
        dropbox) task_source=${OPENCOMMANDER_DROPBOX_OAUTH_FILE:-} ;;
    esac
    if [ -n "$task_source" ]; then
        task_oauth="$task_work/public-oauth/$task_provider-oauth.json"
        PYTHONPATH="$task_root" "$task_root/.venv/bin/python" -m opencommander.public_oauth \
            "$task_provider" "$task_source" "$task_oauth"
        set -- "$@" --add-data "$task_oauth:opencommander/assets"
    fi
done
"$task_root/.venv/bin/python" -m PyInstaller --noconfirm --clean --onedir \
    --name opencommander --workpath "$task_work" --distpath "$task_dist" \
    --specpath "$task_work" --paths "$task_root" \
    --add-data "$task_root/opencommander/assets:opencommander/assets" \
    --add-data "$task_root/opencommander/media_fetch.py:opencommander" \
    --add-data "$task_root/opencommander/gio_bridge.py:opencommander" \
    --add-data "$task_root/opencommander/secret_bridge.py:opencommander" \
    --copy-metadata PySide6-Addons --copy-metadata PySide6-Essentials --copy-metadata shiboken6 --copy-metadata libarchive-c \
    --add-binary "$task_cursor:." \
    --add-binary "$task_archive:." \
    "$@" \
    "$task_root/launcher.py"
task_bundle="$task_dist/opencommander"
cp "$task_root/README.md" "$task_root/CHANGELOG.md" "$task_root/PARITY.md" "$task_root/TESTING.md" "$task_root/THIRD-PARTY.md" "$task_root/install-local.sh" "$task_bundle/"
mkdir -p "$task_bundle/docs"
cp -R "$task_root/docs/handbuch" "$task_bundle/docs/handbuch"
cp -R "$task_root/docs/testplan" "$task_bundle/docs/testplan"
cp -R "$task_root/../release/linux" "$task_bundle/docs/public-release"
cp "$task_root/../LICENSE" "$task_bundle/LICENSE"
cp -R "$task_root/licenses" "$task_bundle/licenses"
cp "$task_runtime/root/usr/share/doc/libxcb-cursor0/copyright" "$task_bundle/licenses/xcb-cursor-copyright"
for task_package in libarchive13t64 libnettle8t64 libacl1 liblzma5 libzstd1 liblz4-1 libbz2-1.0 zlib1g libxml2 libssl3t64 libattr1; do
    if [ -f "/usr/share/doc/$task_package/copyright" ]; then
        cp "/usr/share/doc/$task_package/copyright" "$task_bundle/licenses/$task_package-copyright"
    fi
done
mkdir -p "$task_bundle/source/opencommander"
cp "$task_root"/opencommander/*.py "$task_bundle/source/opencommander/"
cp -R "$task_root/opencommander/assets" "$task_bundle/source/opencommander/assets"
cp "$task_root/launcher.py" "$task_root/requirements.txt" "$task_bundle/source/"
QT_QPA_PLATFORM=offscreen "$task_bundle/opencommander" --smoke-test
(task_arch=$(uname -m); cd "$task_dist"; tar -czf "$task_artifacts/OpenCommander-linux-$task_arch.tar.gz" opencommander)
(cd "$task_artifacts"; sha256sum OpenCommander-linux-*.tar.gz > SHA256SUMS)
printf 'Linux application: %s\n' "$task_bundle/opencommander"
