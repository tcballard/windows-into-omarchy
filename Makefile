.PHONY: test package clean

test:
	python3 image/make_cidata.py
	python3 -m unittest discover -s tests -p 'test*.py' -v
	python3 image/make_cidata.py --check
	python3 image/test_image_contracts.py

package: test
	python3 scripts/package.py

clean:
	rm -rf dist/package dist/Windows-Into-Onarchy-v*.zip dist/Windows-Into-Onarchy-v*.exe dist/SHA256SUMS
