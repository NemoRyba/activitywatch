.PHONY: build test package clean

build:
	poetry install

test:
	poetry run pytest tests
	poetry run aw-watcher-system --help

package:
	pyinstaller aw-watcher-system.spec --clean --noconfirm

clean:
	rm -rf build dist
	rm -rf aw_watcher_system/__pycache__ tests/__pycache__
