#!/usr/bin/env python3
# encoding: utf-8
"""Builds the Elten gettext catalogs for Bop It.

The English msgids are read straight out of the Ruby sources
(src/lib/bop_it_elten/help.rb and engine.rb) so a catalog key can never drift
from the string the code actually passes to _(). The translations live below.
This writes src/locale/<code>.po (readable source) and compiles
src/locale/<code>.mo — the GNU .mo flavour Elten loads (magic 0x950412de, no
hash table), byte-identical to what Mile by Mile ships. test/bop_it_test.rb
re-verifies msgid parity against the Ruby constants in CI, and a missing or
empty translation fails the build here rather than silently giving English
(the _ fallback).

Run from the repo root:
    python3 tools/build_locales.py
"""

import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
LOCALE_DIR = os.path.join(SRC, "locale")
HELP_RB = os.path.join(SRC, "lib", "bop_it_elten", "help.rb")
ENGINE_RB = os.path.join(SRC, "lib", "bop_it_elten", "engine.rb")

# Language code -> English native name (used only for the header).
LANGS = {
    "de": "German", "es": "Spanish", "fr": "French", "it": "Italian",
    "pl": "Polish", "pt": "Portuguese", "ru": "Russian", "tr": "Turkish",
    "uk": "Ukrainian",
}


def unescape_po(s):
    """Unescape the escapes Ruby/PO use inside double-quoted literals."""
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            table = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\"}
            out.append(table.get(n, n))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def read_single_literal(path, name):
    """`    NAME = "value".freeze` on one line."""
    txt = open(path, encoding="utf-8").read()
    m = re.search(r"^\s*" + re.escape(name) + r'\s*=\s*"((?:[^"\\]|\\.)*)"\.freeze\s*$',
                  txt, re.M)
    if not m:
        raise SystemExit("build_locales: no single-line constant %s in %s" % (name, path))
    return unescape_po(m.group(1))


def read_concat_literal(path, name):
    """Adjacent string literals: NAME = "a" followed by "b".freeze lines."""
    txt = open(path, encoding="utf-8").read()
    start = txt.index(name + " = ")
    head = txt[start:txt.index(".freeze", start)]
    pieces = re.findall(r'"((?:[^"\\]|\\.)*)"', head)
    return "".join(unescape_po(p) for p in pieces)


def read_heredoc(path, name, terminator):
    """`    NAME = <<~TERMINATOR` ... `TERMINATOR`, replicating Ruby's <<~:
    dedent by the common leading whitespace of non-blank lines, then chomp the
    single trailing newline (help.rb writes `<<~MARKDOWN.chomp`)."""
    lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
    i = next(k for k, ln in enumerate(lines) if re.search(
        r"\b" + re.escape(name) + r"\s*=\s*<<~" + re.escape(terminator), ln))
    body = []
    j = i + 1
    while lines[j].strip() != terminator:
        body.append(lines[j])
        j += 1
    content = [ln.rstrip("\n") for ln in body]
    non_blank = [ln for ln in content if ln.strip()]
    common = min(len(ln) - len(ln.lstrip(" ")) for ln in non_blank) if non_blank else 0
    dedented = [ln[common:] if ln.startswith(" " * common) else ln for ln in content]
    value = "\n".join(dedented)
    if value.endswith("\n"):
        value = value[:-1]
    return value


def english_msgids():
    """{short name: English msgid}, mirrored from the Ruby constants."""
    return {
        "title": read_single_literal(HELP_RB, "TITLE"),
        "close": read_single_literal(HELP_RB, "CLOSE"),
        "join_beta": read_single_literal(HELP_RB, "JOIN_BETA"),
        "full_help": read_heredoc(HELP_RB, "FULL_HELP", "MARKDOWN"),
        "help_text": read_concat_literal(ENGINE_RB, "HELP_TEXT"),
        # reset_window speaks the plain word 'reset' (hidden test-mode gate).
        "reset": "reset",
    }


# --------------------------------------------------------------------------
# Translations.  Command words and level names stay English everywhere — the
# toy's recorded voice says them in English (bop it / twist it / pull it,
# Solo, Pass It, Novice/Expert/Master, quiet/loud/blasting) and the keys are
# named as they are printed on the keyboard.  Only the surrounding prose and
# the spoken H-help are translated.
# --------------------------------------------------------------------------

SHORT = {
    "title": {
        "de": "Bop It — Hilfe", "es": "Bop It — Ayuda", "fr": "Bop It — Aide",
        "it": "Bop It — Guida", "pl": "Bop It — Pomoc", "pt": "Bop It — Ajuda",
        "ru": "Bop It — Справка", "tr": "Bop It — Yardım", "uk": "Bop It — Довідка",
    },
    "close": {
        "de": "Schließen", "es": "Cerrar", "fr": "Fermer",
        "it": "Chiudi", "pl": "Zamknij", "pt": "Fechar",
        "ru": "Закрыть", "tr": "Kapat", "uk": "Закрити",
    },
    "join_beta": {
        "de": "Der Beta-Testgruppe beitreten",
        "es": "Unirse al grupo de pruebas beta",
        "fr": "Rejoindre le groupe de test bêta",
        "it": "Entra nel gruppo di beta testing",
        "pl": "Dołącz do grupy testów beta",
        "pt": "Entrar no grupo de testes beta",
        "ru": "Вступить в группу бета-тестирования",
        "tr": "Beta testi grubuna katıl",
        "uk": "Долучитися до групи бета-тестування",
    },
    "reset": {
        "de": "reset", "es": "reinicio", "fr": "réinitialisation",
        "it": "reset", "pl": "reset", "pt": "reset",
        "ru": "сброс", "tr": "sıfırla", "uk": "скидання",
    },
}

HELP_TEXT = {
    "de": "Space bop it, Enter twist it, Tab pull it. Space startet das Spiel. "
          "Eine falsche Taste beendet die Runde; Escape schaltet das Spielzeug aus. "
          "Auf dem Startbildschirm ändert Enter die Lautstärke, M den "
          "Schwierigkeitsgrad und Tab wechselt in den Pass-It-Modus. "
          "F1 öffnet die vollständige Hilfe.",
    "es": "Space bop it, Enter twist it, Tab pull it. Space inicia la partida. "
          "Una tecla equivocada termina la ronda; Escape apaga el juguete. "
          "En la pantalla de inicio, Enter cambia el volumen, M el nivel y Tab "
          "cambia al modo Pass It. F1 abre la ayuda completa.",
    "fr": "Space bop it, Enter twist it, Tab pull it. Space démarre la partie. "
          "Une mauvaise touche met fin à la manche ; Escape éteint le jouet. "
          "Sur l'écran d'accueil, Enter change le volume, M le niveau et Tab "
          "passe en mode Pass It. F1 ouvre l'aide complète.",
    "it": "Space bop it, Enter twist it, Tab pull it. Space inizia la partita. "
          "Un tasto sbagliato termina il turno; Escape spegne il giocattolo. "
          "Nella schermata iniziale, Enter cambia il volume, M il livello e Tab "
          "passa alla modalità Pass It. F1 apre la guida completa.",
    "pl": "Space bop it, Enter twist it, Tab pull it. Space rozpoczyna grę. "
          "Zły klawisz kończy rundę; Escape wyłącza zabawkę. "
          "Na ekranie startowym Enter zmienia głośność, M poziom, a Tab "
          "przełącza w tryb Pass It. F1 otwiera pełną pomoc.",
    "pt": "Space bop it, Enter twist it, Tab pull it. Space inicia a partida. "
          "Uma tecla errada encerra a rodada; Escape desliga o brinquedo. "
          "Na tela inicial, Enter muda o volume, M o nível e Tab alterna para "
          "o modo Pass It. F1 abre a ajuda completa.",
    "ru": "Space — bop it, Enter — twist it, Tab — pull it. Space начинает игру. "
          "Неверная клавиша завершает раунд, Escape выключает игрушку. "
          "На стартовом экране Enter меняет громкость, M — уровень, "
          "Tab переключает режим Pass It. F1 — полная справка.",
    "tr": "Space bop it, Enter twist it, Tab pull it. Space oyunu başlatır. "
          "Yanlış bir tuş turu bitirir; Escape oyuncağı kapatır. "
          "Başlangıç ekranında Enter sesi, M seviyeyi değiştirir ve Tab "
          "Pass It moduna geçirir. F1 tam yardımı açar.",
    "uk": "Space — bop it, Enter — twist it, Tab — pull it. Space починає гру. "
          "Помилкова клавіша завершує раунд, Escape вимикає іграшку. "
          "На стартовому екрані Enter змінює гучність, M — рівень, "
          "Tab перемикає режим Pass It. F1 — повна довідка.",
}

FULL_HELP = {
    "de": """# Bop It für Elten 3

Ein schnelles Reaktionsspiel. Das Spielzeug ruft einen Befehl — bop it, twist it oder pull it — und du musst die passende Taste drücken, bevor der Taktgeber abläuft. Eine falsche Taste oder eine Pause beendet die Runde.

## Das Original

Die Spielmechanik stammt vom Bop It Shout-Spielzeug von Hasbro (2008), das den ganzen Raum mitspielen ließ: eine Person hielt das Spielzeug, während alle gemeinsam die Befehle riefen. Dieser Port behält die drei klassischen Bewegungen und lässt den Shout It-Befehl weg.

## Bedienung über die Tasten

- Space — bop it.
- Enter — twist it.
- Tab — pull it.
- Escape — schaltet das Spielzeug aus.

Eine Runde dauert, bis du einen Fehler machst oder 100 richtige Bewegungen schaffst. Die Befehle werden schneller, je länger du durchhältst.

## Auf dem Startbildschirm

Während das Spielzeug "bop it to start" sagt, haben die Tasten zusätzliche Aufgaben:

- Space — startet ein Spiel.
- Enter — ändert die Lautstärke (quiet, loud, blasting), wie der Schalter am echten Spielzeug.
- M — der kleine Knopf am Spielzeugkörper: wähle den Schwierigkeitsgrad.
- Tab — wechselt zwischen Solo und Pass It.
- H — wiederholt die kurze Tastenliste.
- F1 — öffnet diese Seite erneut.

## Schwierigkeitsgrade

Es gibt drei: Novice, Expert und Master. Novice nennt den Befehl beim Namen, Expert spielt den Klang des Spielzeugs, Master mischt beides. Schlage einen Grad mit 100 Bewegungen, um den nächsten freizuschalten.

## Pass It

Reich das Gerät im Raum herum. Wenn das Spielzeug "pass it" sagt, gib es an den nächsten Spieler weiter. Wer einen Fehler macht, scheidet aus; der Letzte, der übrig bleibt, gewinnt.

## Über diesen Port

Geschrieben von Deniz Sincar, erweckt diese Version das Spielzeug auf Elten 3 neu. Die Spiellogik ist eine treue Übernahme seiner ursprünglichen Elten-2-Ausgabe, aufgebaut auf der Bop-It-Shout-Mechanik; die Stimmen und Effektgeräusche wurden von einem echten Bop-It-Gerät aufgenommen. Die Engine ist frei von Elten-Aufrufen gehalten, damit sie für sich getestet werden kann — das hält jede Version stabil.

Viel Spaß — und lass die Hände an den Tasten.""",
    "es": """# Bop It para Elten 3

Un juego de reflejos rapidísimo. El juguete da una orden — bop it, twist it o pull it — y debes pulsar la tecla correcta antes de que se acabe el metrónomo. Una tecla equivocada o una pausa termina la ronda.

## El original

La mecánica está copiada del juguete Bop It Shout de Hasbro (2008), que hacía jugar a toda la sala: una persona sostenía el juguete mientras todos gritaban las órdenes a la vez. Este port conserva los tres movimientos clásicos y deja fuera la orden Shout It.

## Jugar con las teclas

- Space — bop it.
- Enter — twist it.
- Tab — pull it.
- Escape — apaga el juguete.

Una ronda dura hasta que fallas o completas 100 movimientos correctos. Las órdenes se aceleran cuanto más aguantas.

## En la pantalla de inicio

Mientras el juguete dice "bop it to start", las teclas hacen cosas extra:

- Space — empezar una partida.
- Enter — cambiar el volumen (quiet, loud, blasting), como el interruptor del juguete real.
- M — el botón pequeño del cuerpo del juguete: elegir el nivel.
- Tab — alternar entre Solo y Pass It.
- H — repetir la lista breve de teclas.
- F1 — volver a abrir esta página.

## Niveles

Hay tres: Novice, Expert y Master. Novice dice la orden por su nombre, Expert reproduce el sonido del juguete y Master combina ambos. Supera un nivel con 100 movimientos para desbloquear el siguiente.

## Pass It

Pasa el dispositivo por la sala. Cuando el juguete diga "pass it", entrégalo al siguiente jugador. Quien falle queda fuera; el último que quede en pie gana.

## Sobre este port

Escrito por Deniz Sincar, esta versión recrea el juguete en Elten 3. La lógica del juego es un port fiel de su edición original de Elten 2, construido sobre la mecánica de Bop It Shout; las voces y los efectos se grabaron de una unidad Bop It real. El motor se mantiene libre de llamadas a Elten para poder probarlo por sí solo, lo que mantiene sólida cada versión.

Disfrútalo — y mantén las manos en las teclas.""",
    "fr": """# Bop It pour Elten 3

Un jeu de rapidité. Le jouet annonce une commande — bop it, twist it ou pull it — et vous devez appuyer sur la bonne touche avant la fin du métronome. Une mauvaise touche ou une pause met fin à la manche.

## L'original

Les mécaniques sont reprises du jouet Bop It Shout de Hasbro (2008), qui faisait jouer toute la pièce : une personne tenait le jouet pendant que tout le monde criait les commandes en chœur. Ce port conserve les trois gestes classiques et laisse de côté la commande Shout It.

## Jouer avec les touches

- Space — bop it.
- Enter — twist it.
- Tab — pull it.
- Escape — éteint le jouet.

Une manche dure jusqu'à ce que vous manquiez une commande ou que vous réussissiez 100 bons gestes. Les commandes s'accélèrent à mesure que vous survivez.

## Sur l'écran d'accueil

Tant que le jouet dit "bop it to start", les touches font des choses en plus :

- Space — démarrer une partie.
- Enter — changer le volume (quiet, loud, blasting), comme l'interrupteur du vrai jouet.
- M — le petit bouton sur le corps du jouet : choisir le niveau.
- Tab — passer de Solo à Pass It.
- H — répéter la liste courte des touches.
- F1 — rouvrir cette page.

## Niveaux

Il y en a trois : Novice, Expert et Master. Novice annonce la commande par son nom, Expert joue le son du jouet, Master mélange les deux. Battez un niveau avec 100 gestes pour débloquer le suivant.

## Pass It

Faites circuler l'appareil dans la pièce. Quand le jouet dit "pass it", donnez-le au joueur suivant. Celui qui manque est éliminé ; le dernier en lice gagne.

## À propos de ce port

Écrit par Deniz Sincar, cette version recrée le jouet sur Elten 3. La logique du jeu est un port fidèle de son édition Elten 2 d'origine, fondée sur les mécaniques de Bop It Shout ; les voix et les effets ont été enregistrés depuis un vrai Bop It. Le moteur reste exempt d'appels à Elten pour pouvoir être testé seul, ce qui garde chaque version solide.

Amusez-vous bien — et gardez les mains sur les touches.""",
    "it": """# Bop It per Elten 3

Un gioco di riflessi velocissimo. Il giocattolo ordina un comando — bop it, twist it o pull it — e tu devi premere il tasto giusto prima che scada il metronomo. Un tasto sbagliato o una pausa termina il turno.

## L'originale

Le meccaniche sono prese dal giocattolo Bop It Shout della Hasbro (2008), che faceva giocare tutta la stanza: una persona teneva il giocattolo mentre tutti gridavano i comandi insieme. Questo port conserva le tre mosse classiche e lascia fuori il comando Shout It.

## Come si gioca con i tasti

- Space — bop it.
- Enter — twist it.
- Tab — pull it.
- Escape — spegne il giocattolo.

Un turno dura finché non sbagli o non completi 100 mosse corrette. I comandi accelerano più a lungo sopravvivi.

## Nella schermata iniziale

Mentre il giocattolo dice "bop it to start", i tasti fanno cose extra:

- Space — inizia una partita.
- Enter — cambia il volume (quiet, loud, blasting), come l'interruttore del vero giocattolo.
- M — il piccolo pulsante sul corpo del giocattolo: scegli il livello.
- Tab — passa da Solo a Pass It.
- H — ripete il breve elenco dei tasti.
- F1 — riapre questa pagina.

## Livelli

Sono tre: Novice, Expert e Master. Novice dice il nome del comando, Expert riproduce il suono del giocattolo, Master mescola entrambi. Supera un livello con 100 mosse per sbloccare il successivo.

## Pass It

Passa il dispositivo per la stanza. Quando il giocattolo dice "pass it", dallo al giocatore successivo. Chi sbaglia è fuori; l'ultimo rimasto vince.

## Su questo port

Scritto da Deniz Sincar, questa versione ricrea il giocattolo su Elten 3. La logica di gioco è un port fedele della sua edizione originale per Elten 2, costruito sulle meccaniche di Bop It Shout; le voci e gli effetti sonori sono stati registrati da un vero Bop It. Il motore è tenuto libero da chiamate a Elten così può essere testato da solo, il che mantiene solida ogni versione.

Buon divertimento — e tieni le mani sui tasti.""",
    "pl": """# Bop It dla Eltena 3

Szybka gra refleks. Zabawka wypowiada komendę — bop it, twist it lub pull it — a ty musisz nacisnąć właściwy klawisz, zanim skończy się metronom. Zły klawisz albo pauza kończy rundę.

## Oryginał

Mechanika jest skopiowana z zabawki Bop It Shout firmy Hasbro (2008), która angażowała cały pokój: jedna osoba trzymała zabawkę, a wszyscy razem wykrzykiwali komendy. Ten port zachowuje trzy klasyczne ruchy i pomija komendę Shout It.

## Sterowanie klawiszami

- Space — bop it.
- Enter — twist it.
- Tab — pull it.
- Escape — wyłącza zabawkę.

Runda trwa, dopóki nie popełnisz błędu lub nie wykonasz 100 poprawnych ruchów. Komendy przyspieszają, im dłużej wytrzymasz.

## Na ekranie startowym

Dopóki zabawka mówi "bop it to start", klawisze robią dodatkowe rzeczy:

- Space — rozpocznij grę.
- Enter — zmień głośność (quiet, loud, blasting), jak przełącznik na prawdziwej zabawce.
- M — mały przycisk na korpusie zabawki: wybór poziomu.
- Tab — przełączanie między Solo i Pass It.
- H — powtórz krótką listę klawiszy.
- F1 — otwórz ponownie tę stronę.

## Poziomy

Są trzy: Novice, Expert i Master. Novice podaje nazwę komendy, Expert odtwarza dźwięk zabawki, a Master łączy oba. Pokonaj poziom za 100 ruchów, aby odblokować następny.

## Pass It

Podawaj urządzenie po pokoju. Gdy zabawka powie "pass it", przekaż je następnemu graczowi. Kto popełni błąd, odpada; wygrywa ostatnia osoba, która zostanie.

## O tym porcie

Napisany przez Deniza Sincara, ta wersja odtwarza zabawkę na Eltenie 3. Logika gry to wierny port jego oryginalnej edycji na Elten 2, zbudowany na mechanice Bop It Shout; głosy i efekty nagrano z prawdziwego urządzenia Bop It. Silnik jest wolny od wywołań Eltena, dzięki czemu można go testować osobno, co utrzymuje każdą wersję stabilną.

Miłej zabawy — i trzymaj ręce na klawiszach.""",
    "pt": """# Bop It para o Elten 3

Um jogo de reflexos bem rápido. O brinquedo dá um comando — bop it, twist it ou pull it — e você precisa apertar a tecla certa antes que o metrônomo acabe. Uma tecla errada ou uma pausa encerra a rodada.

## O original

A mecânica foi copiada do brinquedo Bop It Shout da Hasbro (2008), que fazia a sala inteira jogar: uma pessoa segurava o brinquedo enquanto todos gritavam os comandos juntos. Este port mantém os três movimentos clássicos e deixa de fora o comando Shout It.

## Jogando com as teclas

- Space — bop it.
- Enter — twist it.
- Tab — pull it.
- Escape — desliga o brinquedo.

Uma rodada dura até você errar ou completar 100 movimentos certos. Os comandos aceleram quanto mais tempo você sobrevive.

## Na tela inicial

Enquanto o brinquedo diz "bop it to start", as teclas fazem coisas extras:

- Space — iniciar uma partida.
- Enter — mudar o volume (quiet, loud, blasting), como o interruptor do brinquedo de verdade.
- M — o botão pequeno no corpo do brinquedo: escolher o nível.
- Tab — alternar entre Solo e Pass It.
- H — repetir a lista curta de teclas.
- F1 — reabrir esta página.

## Níveis

São três: Novice, Expert e Master. Novice chama o comando pelo nome, Expert toca o som do brinquedo, Master mistura os dois. Vença um nível com 100 movimentos para liberar o próximo.

## Pass It

Passe o aparelho pela sala. Quando o brinquedo disser "pass it", entregue-o ao próximo jogador. Quem errar está fora; o último que sobrar vence.

## Sobre este port

Escrito por Deniz Sincar, esta versão recria o brinquedo no Elten 3. A lógica do jogo é um port fiel da edição original para o Elten 2, construído sobre a mecânica do Bop It Shout; as vozes e os efeitos foram gravados de um Bop It real. O motor é mantido livre de chamadas ao Elten para poder ser testado sozinho, o que mantém cada versão sólida.

Divirta-se — e mantenha as mãos nas teclas.""",
    "ru": """# Bop It для Elten 3

Быстрая игра на реакцию. Игрушка выкрикивает команду — bop it, twist it или pull it — а ты должен успеть нажать нужную клавишу, пока не истёк метроном. Неверная клавиша или пауза заканчивают раунд.

## Оригинал

Механика скопирована с игрушки Bop It Shout от Hasbro (2008), которая заставляла играть всю комнату: один держал игрушку, а все вместе выкрикивали команды. Этот порт сохраняет три классических движения и оставляет в стороне команду Shout It.

## Управление клавишами

- Space — bop it.
- Enter — twist it.
- Tab — pull it.
- Escape — выключает игрушку.

Раунд длится, пока ты не ошибёшься или не выполнишь 100 правильных движений. Команды ускоряются, чем дольше ты держишься.

## На стартовом экране

Пока игрушка говорит "bop it to start", клавиши делают дополнительные вещи:

- Space — начать игру.
- Enter — изменить громкость (quiet, loud, blasting), как переключатель на настоящей игрушке.
- M — маленькая кнопка на корпусе игрушки: выбор уровня.
- Tab — переключение между Solo и Pass It.
- H — повторить короткий список клавиш.
- F1 — снова открыть эту страницу.

## Уровни

Их три: Novice, Expert и Master. Novice называет команду словом, Expert проигрывает звук игрушки, Master смешивает оба. Пройди уровень за 100 движений, чтобы открыть следующий.

## Pass It

Передавай устройство по комнате. Когда игрушка говорит "pass it", отдай его следующему игроку. Кто ошибся — выбывает; последний оставшийся побеждает.

## Об этом порте

Написанный Денизом Синкаром, эта версия воссоздаёт игрушку на Elten 3. Игровая логика — точный порт его оригинальной версии для Elten 2, построенный на механике Bop It Shout; голоса и звуковые эффекты записаны с настоящего Bop It. Движок держится свободным от вызовов Elten, чтобы его можно было тестировать отдельно, что делает каждый релиз надёжным.

Приятной игры — и держи руки на клавишах.""",
    "tr": """# Elten 3 için Bop It

Çok hızlı bir refleks oyunu. Oyuncak bir komut söyler — bop it, twist it ya da pull it — ve sen metronom bitmeden doğru tuşa basmalısın. Yanlış bir tuş veya bir duraklama turu bitirir.

## Orijinal

Mekanikler Hasbro'nun Bop It Shout (2008) oyuncağından alınmıştır; o oyuncak bütün odayı oynatırdı: biri oyuncağı tutar, herkes birlikte komutları bağırırdı. Bu sürüm üç klasik hareketi korur ve Shout It komutunu dışarıda bırakır.

## Tuşlarla oynamak

- Space — bop it.
- Enter — twist it.
- Tab — pull it.
- Escape — oyuncağı kapatır.

Bir tur, hata yapana ya da 100 doğru hareketi tamamlayana kadar sürer. Hayatta kaldıkça komutlar hızlanır.

## Başlangıç ekranında

Oyuncak "bop it to start" derken tuşlar ekstra işler yapar:

- Space — oyun başlatır.
- Enter — ses seviyesini değiştirir (quiet, loud, blasting), tıpkı gerçek oyuncaktaki düğme gibi.
- M — oyuncağın gövdesindeki küçük düğme: seviyeyi seçer.
- Tab — Solo ile Pass It arasında geçiş yapar.
- H — kısa tuş listesini tekrar söyler.
- F1 — bu sayfayı yeniden açar.

## Seviyeler

Üç tane var: Novice, Expert ve Master. Novice komutu adıyla söyler, Expert oyuncağın sesini çalar, Master ikisini karıştırır. Bir seviyeyi 100 hareketle bitirip sıradakini açarsın.

## Pass It

Cihazı odada elden ele dolaştırın. Oyuncak "pass it" dediğinde cihazı sıradaki oyuncuya verin. Hata yapan oyundan çıkar; ayakta kalan son kişi kazanır.

## Bu sürüm hakkında

Deniz Sincar tarafından yazılan bu sürüm, oyuncağı Elten 3 üzerinde yeniden yaratıyor. Oyun mantığı, onun Elten 2'deki özgün sürümünün sadık bir portudur ve Bop It Shout mekaniğine dayanır; sesler ve efektler gerçek bir Bop It cihazından kaydedilmiştir. Motor, Elten çağrılarından arındırılmıştır ki kendi başına test edilebilsin; bu da her sürümü sağlam tutar.

İyi eğlenceler — ve ellerini tuşlardan ayırma.""",
    "uk": """# Bop It для Elten 3

Швидка гра на реакцію. Іграшка вигукує команду — bop it, twist it або pull it — і ти маєш натиснути правильну клавішу, поки не вичерпався метроном. Помилкова клавіша або пауза завершує раунд.

## Оригінал

Механіку скопійовано з іграшки Bop It Shout від Hasbro (2008), яка змушувала грати всю кімнату: одна людина тримала іграшку, а всі разом вигукували команди. Цей порт зберігає три класичні рухи й лишає позаду команду Shout It.

## Керування клавішами

- Space — bop it.
- Enter — twist it.
- Tab — pull it.
- Escape — вимикає іграшку.

Раунд триває, доки не помилишся або не виконаєш 100 правильних рухів. Команди пришвидшуються, чим довше ти тримаєшся.

## На стартовому екрані

Поки іграшка каже "bop it to start", клавіші роблять додаткові речі:

- Space — розпочати гру.
- Enter — змінити гучність (quiet, loud, blasting), як перемикач на справжній іграшці.
- M — маленька кнопка на корпусі іграшки: вибір рівня.
- Tab — перемикання між Solo та Pass It.
- H — повторити короткий список клавіш.
- F1 — відкрити цю сторінку знову.

## Рівні

Їх три: Novice, Expert та Master. Novice називає команду словом, Expert відтворює звук іграшки, Master змішує обидва. Пройди рівень за 100 рухів, щоб відкрити наступний.

## Pass It

Передавай пристрій по кімнаті. Коли іграшка каже "pass it", віддай його наступному гравцеві. Хто помилиться — вибуває; останній, хто лишився, перемагає.

## Про цей порт

Написаний Денізом Синкаром, ця версія відтворює іграшку на Elten 3. Ігрова логіка — це точний порт його оригінальної версії для Elten 2, побудований на механіці Bop It Shout; голоси й звукові ефекти записано зі справжнього Bop It. Рушій тримається вільним від викликів Elten, щоб його можна було тестувати окремо, що робить кожен реліз надійним.

Гарної гри — і тримай руки на клавішах.""",
}


def ensure_translated(kind, code, value, english):
    if value is None or not value.strip():
        raise SystemExit("build_locales: %s translation for %s is empty" % (code, kind))
    # The spoken 'reset' word is a hidden developer cue; keeping the English
    # word there is legitimate, so only guard the real user-facing strings.
    if kind != "reset" and value.strip() == english.strip() and len(english) > 4:
        raise SystemExit("build_locales: %s translation for %s equals English" % (code, kind))


def po_fragment(value, with_eol):
    esc = value.replace("\\", "\\\\").replace('"', '\\"')
    return '"%s%s"' % (esc, "\\n" if with_eol else "")


def entry_po_lines(kind, value):
    """`msgid "..."` for single-line values, otherwise `msgid ""` + fragments."""
    lines = [kind + ' ""']
    parts = value.split("\n")
    for i, part in enumerate(parts):
        last = i == len(parts) - 1
        with_eol = not (last and not value.endswith("\n"))
        lines.append(po_fragment(part, with_eol))
    return lines


def write_po(path, entries):
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        for msgid, msgstr in entries:
            fh.write("\n".join(entry_po_lines("msgid", msgid)))
            fh.write("\n")
            fh.write("\n".join(entry_po_lines("msgstr", msgstr)))
            fh.write("\n\n")


def write_mo(path, entries):
    n = len(entries)
    o_off, t_off = 28, 28 + n * 8
    str_off = t_off + n * 8
    out = bytearray()
    out += struct.pack("<7I", 0x950412DE, 0, n, o_off, t_off, 0, 0)
    offset = str_off
    for msgid, _ in entries:
        b = msgid.encode("utf-8")
        out += struct.pack("<II", len(b), offset)
        offset += len(b) + 1
    for _, msgstr in entries:
        b = msgstr.encode("utf-8")
        out += struct.pack("<II", len(b), offset)
        offset += len(b) + 1
    for msgid, _ in entries:
        out += msgid.encode("utf-8") + b"\0"
    for _, msgstr in entries:
        out += msgstr.encode("utf-8") + b"\0"
    with open(path, "wb") as fh:
        fh.write(bytes(out))


def main():
    en = english_msgids()
    os.makedirs(LOCALE_DIR, exist_ok=True)
    for code in LANGS:
        header = ("Project-Id-Version: BopIt 0.1.4\n"
                  "MIME-Version: 1.0\n"
                  "Content-Type: text/plain; charset=UTF-8\n"
                  "Content-Transfer-Encoding: 8bit\n"
                  "Language: %s\n") % code
        body = [
            ("title", SHORT["title"][code]),
            ("close", SHORT["close"][code]),
            ("join_beta", SHORT["join_beta"][code]),
            ("reset", SHORT["reset"][code]),
            ("help_text", HELP_TEXT[code]),
            ("full_help", FULL_HELP[code]),
        ]
        entries = [("", header)]
        for kind, msgstr in body:
            ensure_translated(kind, code, msgstr, en[kind])
            entries.append((en[kind], msgstr))
        # .mo: header first, the rest sorted by msgid bytes (same as Mile's po2mo).
        ordered = [entries[0]] + sorted(entries[1:], key=lambda e: e[0].encode("utf-8"))
        po_path = os.path.join(LOCALE_DIR, code + ".po")
        mo_path = os.path.join(LOCALE_DIR, code + ".mo")
        write_po(po_path, entries)
        write_mo(mo_path, ordered)
        full_n = len(en["full_help"])
        print("%s: 6 entries (full_help %d->%d chars) -> %s" %
              (code, full_n, len(FULL_HELP[code]), os.path.basename(mo_path)))
    print("OK: %d locales in %s" % (len(LANGS), LOCALE_DIR))
    return 0


if __name__ == "__main__":
    sys.exit(main())
