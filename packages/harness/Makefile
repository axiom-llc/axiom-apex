.PHONY: test verify

test:
	PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=. python -m unittest discover -s tests -p 'test_*.py' -v

verify:
	sh scripts/verify.sh
