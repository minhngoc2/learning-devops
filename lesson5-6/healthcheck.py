from urllib.request import urlopen

urlopen("http://localhost:8000/health", timeout=2).close()
