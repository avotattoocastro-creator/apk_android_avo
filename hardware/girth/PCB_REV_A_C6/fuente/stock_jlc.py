"""Stock, price and library type (Basic/Extended) of each part at JLCPCB, queried from the CI runner.

Usage: python3 stock_jlc.py out_dir C2911374 C3013922 ... [--search LSM6DSV16XTR ...]
Writes out_dir/stock_jlc.json (parsed) and out_dir/stock_jlc_raw/*.json (raw answers, as evidence),
with the UTC date of the query. Nothing is assumed: a part without an answer is reported as "sin respuesta".
"""
import datetime
import json
import os
import sys
import time
import urllib.request

API = "https://jlcpcb.com/api/overseas-pcb-order/v1/shoppingCart/smtGood/selectSmtComponentList"
HDR = {"Content-Type": "application/json", "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) avo-girth-ci",
       "Accept": "application/json"}


def query(keyword):
    body = json.dumps({"keyword": keyword, "currentPage": 1, "pageSize": 25, "searchSource": "search"}).encode()
    req = urllib.request.Request(API, data=body, headers=HDR, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())


def parse(js):
    out = []
    data = (js.get("data") or {})
    lst = ((data.get("componentPageInfo") or {}).get("list")) or []
    for c in lst:
        out.append(dict(
            lcsc=c.get("componentCode"), mpn=c.get("componentModelEn"), maker=c.get("componentBrandEn"),
            package=c.get("componentSpecificationEn"), stock=c.get("stockCount"),
            library=c.get("componentLibraryType"),  # "base" = Basic, "expand" = Extended
            prices=[(p.get("startNumber"), p.get("productPrice")) for p in (c.get("componentPrices") or [])],
            describe=c.get("describe")))
    return out


def main():
    od = sys.argv[1]
    args = sys.argv[2:]
    codes, searches = [], []
    tgt = codes
    for a in args:
        if a == "--search":
            tgt = searches
            continue
        tgt.append(a)
    os.makedirs(os.path.join(od, "stock_jlc_raw"), exist_ok=True)
    res = dict(date_utc=datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC"), api=API, parts={}, search={})
    for k in codes + searches:
        try:
            js = query(k)
            json.dump(js, open(os.path.join(od, "stock_jlc_raw", k + ".json"), "w"), indent=1)
            items = parse(js)
            if k in codes:
                hit = [i for i in items if i["lcsc"] == k]
                res["parts"][k] = hit[0] if hit else dict(lcsc=k, error="sin respuesta para este código")
            else:
                res["search"][k] = items[:10]
        except Exception as e:  # network / format: keep the error as evidence
            (res["parts"] if k in codes else res["search"])[k] = dict(lcsc=k, error=repr(e)[:300])
        time.sleep(0.7)
    json.dump(res, open(os.path.join(od, "stock_jlc.json"), "w"), indent=1, ensure_ascii=False)
    for k, v in res["parts"].items():
        print(k, v.get("mpn"), "stock", v.get("stock"), v.get("library"), (v.get("prices") or [None])[0], v.get("error", ""))
    for k, v in res["search"].items():
        print("search", k, [(i.get("lcsc"), i.get("mpn"), i.get("stock"), i.get("library")) for i in v] if isinstance(v, list) else v)


if __name__ == "__main__":
    main()
