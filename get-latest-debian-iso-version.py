#!/usr/bin/env python3

import re
import urllib.request
from bs4 import BeautifulSoup

debian_base_url = "https://cdimage.debian.org/mirror/cdimage/archive"
sha256_hash_file = "sha256_hashes"

if __name__ == '__main__':
    with urllib.request.urlopen(debian_base_url) as response:
        html = response.read()
        status = response.status

    soup = BeautifulSoup(html, 'html.parser')

    versions = []
    for td in soup.find_all("td", **{ 'class': "indexcolname" }):
        href = td.find('a').get('href')
        if re.compile(r'[0-9]*\.[0-9]\.[0-9]/').match(href):
            versions.append([int(s) for s in href[:-1].split('.')])
    versions.sort()
    latest_version = '.'.join([str(s) for s in versions[-1]])
    latest_directory_url = f'{debian_base_url}/{latest_version}/amd64/iso-cd/'
    latest_iso_filename = f'debian-{latest_version}-amd64-netinst.iso'
    latest_iso_url = latest_directory_url + latest_iso_filename
    latest_hash_url = latest_directory_url + 'SHA256SUMS'

    with urllib.request.urlopen(latest_hash_url) as response:
        for line in response.readlines():
            sha256,filename = re.compile('([0-9a-f]*)\\s*([^\\s]*)').match(
                line.decode("utf-8", "strict")).groups()
            if filename == latest_iso_filename:
                latest_iso_hash = sha256

    # TODO: in the future we may need to replace one line
    with open(sha256_hash_file, 'w') as f:
        f.write(f"{latest_iso_hash}  debian-amd64-netinst.iso\n")

    with open("generated-makefile-variables", 'w') as f:
        f.write(f"DISTRO_ISO_URL={latest_iso_url}\n")
