"""Batch 5 colourways (2026-11-04, "more clothes"): new looks cut from the shipped Blender builders, so every one inherits the vetted fit (mouth keep-out,
Pip's spikes, Lavender's wings, Moss's daisy, Teddy / Panda ears). Neck and body pieces keep their loops / bands clear of the mouth ellipse and the y<=0.51 jersey line;
head pieces sit on the same hat anchor as the other hats.
  sunny bandana (neck)      honey jersey bib / mint jersey bib (body)      plum cosy scarf (neck)      honey bucket hat (head)      mint pom-pom beanie (head)
"""
from kit5 import *
import items3
import items7
import items2_head as I2H
import items_head as IH

NEW = ('bandana_sun', 'bib_honey', 'bib_mint', 'scarf_plum', 'bucket_hat_honey', 'beanie_mint')
PLUM = hx('#7A5BB5')

def _as(fn, title, price, tags, **kw):
    def build(**k):
        meta = fn(**kw)
        meta.update(title=title, price=price, tags=tags)
        return meta
    return build

REG = [
    ('bandana_sun', _as(items7.bandana, 'Sunny bandana', 25, ['cool', 'sporty'], main=HONEY, dots=CREAM, trim=CREAM), dict(), NECK_ANCHOR),
    ('bib_honey', _as(items7.bib, 'Honey jersey bib', 20, ['sporty'], field=HONEY, trim=CREAM), dict(), BIB_ANCHOR),
    ('bib_mint', _as(items7.bib, 'Mint jersey bib', 20, ['sporty'], field=CREAM, trim=MINT), dict(), BIB_ANCHOR),
    ('scarf_plum', _as(items3.scarf, 'Plum cosy scarf', 35, ['cute', 'sweet'], a=PLUM, b=CREAM), dict(), NECK_ANCHOR),
    ('bucket_hat_honey', _as(I2H.bucket_hat, 'Honey bucket hat', 40, ['cool', 'sporty'], main=HONEY, band=CREAM), dict(), H),
    ('beanie_mint', _as(IH.beanie, 'Mint pom-pom beanie', 40, ['cute', 'sweet'], main=MINT, cuff=CREAM, pom=HONEY), dict(), H),
]
VARIANTS = []
