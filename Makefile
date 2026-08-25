.PHONY: test package clean

test:
	python3 tests/test_contracts.py

package: test
	python3 scripts/package.py

clean:
	rm -rf dist/package dist/Windows-Into-Omarchy-v*.zip dist/SHA256SUMS
