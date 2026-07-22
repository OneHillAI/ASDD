# Minimal shim so `pip install -e .` (editable) works across pip versions; the real
# metadata lives in pyproject.toml.
#
# It also stages the operate kit into asdd_kit/ at BUILD time, so an installed wheel
# carries the templates `asdd init` copies. Without this the wheel ships only the
# launcher and every subcommand fails on a missing script.
import os
import shutil

from setuptools import setup
from setuptools.command.build_py import build_py

HERE = os.path.dirname(os.path.abspath(__file__))
# Exactly what cli/init.sh copies from the source tree, plus what the CLI dispatches to.
KIT = [".asdd.example.yml", "AGENTS.md", "asdd-kit.yml", "cli", "recipes", "validation", ".github"]
_IGNORE = shutil.ignore_patterns("__pycache__", "*.pyc", "node_modules", "build")


class build_py_with_kit(build_py):
    def run(self):
        pkg = os.path.join(HERE, "asdd_kit")
        for name in KIT:
            src, dst = os.path.join(HERE, name), os.path.join(pkg, name)
            if os.path.isdir(src):
                if os.path.exists(dst):
                    shutil.rmtree(dst)
                shutil.copytree(src, dst, ignore=_IGNORE)
            elif os.path.isfile(src):
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(src, dst)
        super().run()


setup(cmdclass={"build_py": build_py_with_kit})
