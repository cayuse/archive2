"""Name normalisation for matching titles, artists and albums, in every script and language.

The library holds Latin with accents (Spanish, French, Vietnamese), Cyrillic (Russian, Ukrainian),
Greek, Armenian, Georgian, Hebrew, Arabic, Hangul, kana and CJK. A key must keep the letters of all of
them: an ASCII-only key turns every Cyrillic or Korean title into "" and they all "match" each other.

  norm_name("Кино")                == "кино"
  norm_name("La gloria eres tú")   == norm_name("La gloria eres tu") == "lagloriaerestu"
  norm_name("Song (2011 Remaster)") == norm_name("Song")

Rules: Unicode NFKC (full-width forms and ligatures become plain), casefold (ß -> ss, Turkish İ),
accents dropped (marks removed after NFD, then recomposed: é -> e, й -> и, ё -> е, ї -> і), every
character that is not a letter or digit in any script dropped (spaces, punctuation, quotes, dashes).
Hangul and CJK have no case or accents and pass through unchanged. Pure standard library.
"""
import re
import unicodedata

# version / remaster notes in brackets that do not change the song; Latin and Cyrillic words
_VERSION_NOTE = re.compile(
    r"[\(\[][^)\]]*(remaster|version|edit|mono|stereo|mix|live|ремастер|версия|версія|редакция|микс|"
    r"концерт|live)[^)\]]*[\)\]]", re.I)
_NOT_WORD = re.compile(r"[\W_]+")


def fold(s):
    """casefolded, accent-free, NFC text (spaces and punctuation kept)"""
    s = unicodedata.normalize("NFKC", s or "").casefold()
    s = "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")
    return unicodedata.normalize("NFC", s)


def norm_name(s):
    """matching key for a title, artist or album: letters and digits of any script only"""
    s = _VERSION_NOTE.sub("", unicodedata.normalize("NFKC", s or ""))
    return _NOT_WORD.sub("", fold(s))


def norm_album(s):
    """matching key for an album title: every bracketed note dropped (deluxe, remastered, disc 2)"""
    s = re.sub(r"[\(\[][^)\]]*[\)\]]", "", unicodedata.normalize("NFKC", s or ""))
    return _NOT_WORD.sub("", fold(s))


def pad(s, width):
    """cut / pad to a column width on screen: Hangul, kana and CJK take two columns each"""
    out, w = [], 0
    for c in s or "":
        cw = 2 if unicodedata.east_asian_width(c) in "WF" else 0 if unicodedata.combining(c) else 1
        if w + cw > width:
            break
        out.append(c); w += cw
    return "".join(out) + " " * (width - w)


# hits packages and compilations, in the languages the library holds most
COMPILATION = re.compile(
    r"greatest|best of|\bhits\b|collection|essential|anthology|\bgold\b|now that|top \d|radio|promo only|"
    r"sampler|\bvol(ume)?\b|classics|ultimate|totally|100%|compilation|various|soundtrack|\bdisco\b.*\d|"
    r"\d+ (years|años)|grandes [eé]xitos|lo mejor|éxitos|exitos|meilleur|le meilleur|plus grands succès|"
    r"сборник|лучшее|лучшие песни|избранное|збірка|найкращ|베스트|히트|ベスト|精选|精選|金曲",
    re.I)


if __name__ == "__main__":
    # self-test: python3 textnorm.py
    same = [("La gloria eres tú", "La gloria eres tu"), ("Desde que no estás aquí", "Desde que no estas aqui"),
            ("Кино", "КИНО"), ("Ёлка", "Елка"), ("Granddaddy’s Gun", "Granddaddy's Gun"),
            ("Song (2011 Remaster)", "Song"), ("Песня (ремастер 2009)", "Песня"),
            ("Ｆｕｌｌ　Ｗｉｄｔｈ", "full width"), ("Straße", "STRASSE"), ("Tu Quyên", "Tu Quyen"),
            ("Café Tacvba", "Cafe Tacvba"), ("A★Teens", "A Teens"), ("Обійми", "обійми")]
    differ = [("Кино", "Кіно та"), ("노이즈", "고개숙인"), ("Кино", ""), ("Океан Ельзи", "Кино"),
              ("حەسەن زیرەک", ""), ("横山勝也", ""), ("Արամ Խաչատրյան", ""), ("გია ყანჩელი", "")]
    bad = 0
    for a, b in same:
        ok = norm_name(a) == norm_name(b) and norm_name(a)
        bad += not ok
        print(f"{'ok ' if ok else 'BAD'} same    {a!r} {b!r} -> {norm_name(a)!r} {norm_name(b)!r}")
    for a, b in differ:
        ok = norm_name(a) != norm_name(b)
        bad += not ok
        print(f"{'ok ' if ok else 'BAD'} differ  {a!r} {b!r} -> {norm_name(a)!r} {norm_name(b)!r}")
    for t, want in [("Grandes Éxitos", True), ("Лучшее", True), ("Збірка хітів", True), ("베스트 앨범", True),
                    ("Dandelion", False), ("Группа крови", False)]:
        ok = bool(COMPILATION.search(t)) == want
        bad += not ok
        print(f"{'ok ' if ok else 'BAD'} compilation {t!r} -> {bool(COMPILATION.search(t))}")
    raise SystemExit(bad)
