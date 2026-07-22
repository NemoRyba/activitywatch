.PHONY: build test package clean

build:
	poetry install

test:
	poetry run pytest tests
	poetry run aw-watcher-audio --help

package:
	pyinstaller aw-watcher-audio.spec --clean --noconfirm

clean:
	rm -rf build dist
	rm -rf aw_watcher_audio/__pycache__ tests/__pycache__

