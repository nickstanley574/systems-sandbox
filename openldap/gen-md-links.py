# importing the modules
from mechanize import Browser
import requests

f = open("resources.txt", "r")
resources = f.read().splitlines()

links = {}

for url in resources:
    try:
        br = Browser()
        br.addheaders = [('User-agent', 'Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.0.1) Gecko/2008071615 Fedora/3.0.1-1.fc9 Firefox/3.0.1')]
        br.open(url)
        title = br.title()
        links[title] = f"[{title}]({url})"
    except Exception as e:
        print(f"ERROR {url} - {e}")
for k in sorted(links.keys()):
    print(links[k])