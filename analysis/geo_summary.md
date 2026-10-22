# Where scanners come from: country and ASN (KAP-72)

*IP Geolocation by DB-IP (https://db-ip.com).* Data: DB-IP Lite country and ASN databases (CC BY 4.0), looked up on the real IP inside `anonymise_requests()` before hashing.

## Scope

- Only direct-to-origin requests (`via_cloudflare == FALSE`): 153,792 requests, 4,662 distinct clients. Requests through Cloudflare carry an edge address, so country and ASN are `NA` there.
- Only countries and ASNs with at least 5 distinct clients are listed. Aggregates only.
- Geolocation is approximate (country level); an ASN identifies the network operator, not the person.

## Client class by hosting provider

Hosting/cloud = the AS organisation name matches one of these keywords (case-insensitive): 
amazon, google, microsoft, digitalocean, digital ocean, ovh, hetzner, linode, akamai, alibaba, tencent, contabo, m247, vultr, choopa, oracle, cloud, hosting, datacamp, leaseweb, scaleway, online s.a.s, ionos, stark industries, pq hosting, kamatera, colocrossing, psychz.
The list is a heuristic: broad words like `cloud` or `hosting` also catch some non-hosting networks, and VPN or proxy providers outside the list are missed.

| class | requests | clients | requests from hosting ASNs | clients in hosting ASNs |
|---|---|---|---|---|
| scanner | 119,915 | 3,211 | 28% | 48% |
| internal | 23,730 | 119 | 0% | 0% |
| unknown | 5,555 | 1,621 | 45% | 63% |
| bot | 4,592 | 636 | 25% | 68% |

**Scanners: 28% of scanner requests and 48% of scanner clients sit in hosting/cloud ASNs.**

## Top countries of scanner traffic

| country | requests | clients | share |
|---|---|---|---|
| US | 43,102 | 1,267 | 35.9% |
| DE | 26,763 | 518 | 22.3% |
| FR | 9,778 | 105 | 8.2% |
| NL | 8,801 | 213 | 7.3% |
| SG | 4,894 | 60 | 4.1% |
| BG | 2,370 | 8 | 2.0% |
| AD | 2,294 | 23 | 1.9% |
| GB | 2,200 | 209 | 1.8% |
| FI | 1,571 | 8 | 1.3% |
| VN | 1,035 | 38 | 0.9% |

![Top countries per class](figures/15_top_countries_by_class.png)

## Top ASNs of scanner traffic

| asn | organisation | requests | clients | hosting |
|---|---|---|---|---|
| AS202412 | Omegatech LTD | 19,126 | 20 | no |
| AS396982 | Google LLC | 18,111 | 448 | yes |
| AS208137 | Feo Prest SRL | 15,075 | 9 | no |
| AS201814 | MEVSPACE sp. z o.o. | 9,296 | 10 | no |
| AS211590 | Bucklog SARL | 8,162 | 9 | no |
| AS31898 | Oracle Corporation | 2,613 | 19 | yes |
| AS14061 | DigitalOcean, LLC | 2,599 | 253 | yes |
| AS48090 | TECHOFF SRV LIMITED | 2,294 | 23 | no |
| AS197170 | TechTies Inc. | 2,063 | 39 | no |
| AS8075 | Microsoft Corporation | 1,847 | 402 | yes |
| AS16509 | Amazon.com, Inc. | 1,376 | 15 | yes |
| AS63949 | Akamai Technologies, Inc. | 1,355 | 80 | yes |
| AS401626 | Netiface America, Inc. | 1,139 | 10 | no |
| AS51396 | Pfcloud UG (haftungsbeschrankt) | 1,078 | 39 | yes |
| AS197769 | VPS Dedicated LLC | 769 | 21 | no |

![Top scanner ASNs](figures/16_top_asns_scanners.png)

