"""Build wheel from sdist from exact HEAD; never create tags or publish."""
import argparse
import gzip
import hashlib
import importlib.metadata
import io
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import tarfile
import tempfile
import tomllib


def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--tag', default='')
    args = parser.parse_args()
    revision = git('rev-parse', 'HEAD')
    project = tomllib.loads(git('show', 'HEAD:pyproject.toml'))['project']
    if args.tag:
        if not re.fullmatch(r'v\d+\.\d+\.\d+', args.tag) or args.tag != 'v' + project['version']:
            parser.error('tag must equal v<pyproject.toml version>')
        if git('rev-parse', '--verify', f'refs/tags/{args.tag}^{{commit}}') != revision:
            parser.error('tag must point to checked-out HEAD')
    # Uncommitted source is deliberately never included.
    epoch = int(git('show', '-s', '--format=%ct', 'HEAD'))
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, SOURCE_DATE_EPOCH=str(epoch), PYTHONHASHSEED='0')
    with tempfile.TemporaryDirectory(prefix='axiom-build-') as tmp:
        source = Path(tmp) / 'source'
        source.mkdir()
        archive = subprocess.check_output(['git', 'archive', revision])
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(source, filter='data')
        subprocess.run([sys.executable, '-m', 'build', '--sdist', '--no-isolation',
                        '--outdir', str(output), str(source)], env=env, check=True)
        sdist, = output.glob('*.tar.gz')
        # setuptools' sdist timestamps/ownership otherwise depend on the builder.
        normalized = io.BytesIO()
        with tarfile.open(sdist) as original:
            with gzip.GzipFile(fileobj=normalized, mode='wb', filename='', mtime=epoch) as gz:
                with tarfile.open(fileobj=gz, mode='w', format=tarfile.PAX_FORMAT) as tar:
                    for member in sorted(original.getmembers(), key=lambda item: item.name):
                        content = original.extractfile(member) if member.isfile() else None
                        member.mtime = epoch
                        member.uid = member.gid = 0
                        member.uname = member.gname = ''
                        member.pax_headers = {}
                        tar.addfile(member, content)
        sdist.write_bytes(normalized.getvalue())
        unpacked = Path(tmp) / 'sdist'
        with tarfile.open(sdist) as tar:
            tar.extractall(unpacked, filter='data')
        package, = unpacked.iterdir()
        subprocess.run([sys.executable, '-m', 'build', '--wheel', '--no-isolation',
                        '--outdir', str(output), str(package)], env=env, check=True)
    info = dict(project=project['name'], version=project['version'], revision=revision,
                source_date_epoch=epoch, python=platform.python_version(),
                tools={name: importlib.metadata.version(name) for name in
                       ('build', 'setuptools', 'wheel', 'packaging', 'pyproject_hooks')})
    (output / 'BUILD-INFO.json').write_text(json.dumps(info, indent=2, sort_keys=True) + '\n')
    checksums = ''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n'
                        for p in sorted(output.iterdir()))
    (output / 'SHA256SUMS').write_text(checksums)
    print(checksums, end='')


if __name__ == '__main__':
    main()
