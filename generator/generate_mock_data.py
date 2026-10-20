#!/usr/bin/env python3
"""Generate mock Voice-of-the-Customer data for the Looker demo.

Only two "source" datasets are produced, mirroring what Genesys would deliver:

  transcripts.jsonl            one row per conversation that has a (PII-redacted) transcript
  interaction_metrics.jsonl    simple operational metrics per conversation (+ .csv copy)

Storylines are planted relative to --end so the demo always looks "current":

  * Price plan migration email (END-28)  -> billing spike, long AHT, low CSAT, churn, competitors
  * Router firmware 4.2.1 on Nova X3 (END-12) -> brand-new, growing Wi-Fi issue with repeat contacts
  * Number porting self-service failures  -> chat-then-call journey gap, repeat contacts
  * BankID app login incident (END-70..END-57), concentrated in Skåne
  * Broadband delivery delays, worst in the "OpenNet Syd" network, new customers
  * Summer roaming, iPhone launch eSIM bump, plus steady baseline topics

Also written, for QA and as a no-Gemini fallback:

  ground_truth.jsonl                        labels used to generate each conversation
  fallback_conversation_insights.jsonl      rows shaped exactly like the Gemini output table
  fallback_topic_catalog.jsonl
  fallback_topic_recommendations.jsonl
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import random
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from typing import Callable
from zoneinfo import ZoneInfo

TZ = ZoneInfo("Europe/Stockholm")

REGIONS = {
    "Stockholm": 0.30,
    "Västra Götaland": 0.18,
    "Skåne": 0.15,
    "Östergötland": 0.06,
    "Uppsala": 0.05,
    "Västerbotten": 0.04,
    "Norrbotten": 0.03,
    "Other": 0.19,
}
NETWORK_BY_REGION = {
    "Stockholm": "Nordfiber",
    "Uppsala": "Nordfiber",
    "Östergötland": "Nordfiber",
    "Västra Götaland": "Stadsnät Väst",
    "Skåne": "OpenNet Syd",
    "Västerbotten": "IP-Fiber Norr",
    "Norrbotten": "IP-Fiber Norr",
}
NETWORKS = ["Nordfiber", "Stadsnät Väst", "OpenNet Syd", "IP-Fiber Norr"]

MOBILE_COMPETITORS = [
    ("Tre", "100 GB for 299 kronor a month", "100 GB för 299 kronor i månaden", 299),
    ("Tele2", "unlimited data for 349 kronor a month", "obegränsad surf för 349 kronor i månaden", 349),
    ("Comviq", "40 GB for 199 kronor a month", "40 GB för 199 kronor i månaden", 199),
    ("Hallon", "30 GB for 149 kronor a month", "30 GB för 149 kronor i månaden", 149),
    ("Telia", "50 GB for 329 kronor a month", "50 GB för 329 kronor i månaden", 329),
]
FIXED_COMPETITORS = [
    ("Bahnhof", "fiber 250 Mbit for 299 kronor a month", "fiber 250 Mbit för 299 kronor i månaden", 299),
    ("Telia", "fiber 500 Mbit for 349 kronor a month", "fiber 500 Mbit för 349 kronor i månaden", 349),
]

MONTHS_EN = ["January", "February", "March", "April", "May", "June", "July", "August",
             "September", "October", "November", "December"]
MONTHS_SV = ["januari", "februari", "mars", "april", "maj", "juni", "juli", "augusti",
             "september", "oktober", "november", "december"]
WEEKDAYS_EN = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
WEEKDAYS_SV = ["måndags", "tisdags", "onsdags", "torsdags", "fredags", "lördags", "söndags"]


def fmt_date(d: date, lang: str) -> str:
    return f"{d.day} {MONTHS_SV[d.month - 1]}" if lang == "sv" else f"{MONTHS_EN[d.month - 1]} {d.day}"


def fmt_weekday(d: date, lang: str) -> str:
    return WEEKDAYS_SV[d.weekday()] if lang == "sv" else WEEKDAYS_EN[d.weekday()]


@dataclass
class Timeline:
    end: date

    @property
    def start(self) -> date:
        return self.end - timedelta(days=111)

    @property
    def migration_email(self) -> date:
        return self.end - timedelta(days=28)

    @property
    def firmware_push(self) -> date:
        return self.end - timedelta(days=12)

    @property
    def firmware_known(self) -> date:
        return self.end - timedelta(days=7)

    @property
    def bankid_incident(self) -> tuple[date, date]:
        return self.end - timedelta(days=70), self.end - timedelta(days=57)

    @property
    def iphone_launch(self) -> date:
        return self.end - timedelta(days=32)

    @property
    def summer_end(self) -> date:
        return self.start + timedelta(days=45)


@dataclass
class Customer:
    key: str
    business_type: str
    region: str
    customer_since: date
    has_mobile: bool
    has_fixed: bool
    has_tv: bool
    router_model: str | None
    network_operator: str | None
    churn_date: date | None = None

    def tenure_months(self, d: date) -> int:
        return max(0, (d - self.customer_since).days // 30)


@dataclass
class Ctx:
    rng: random.Random
    lang: str
    channel: str
    contact_date: date
    customer: Customer
    tl: Timeline
    followup: bool
    prev_date: date | None
    resolved: bool
    self_service: bool
    churn_intent: bool
    v: dict = field(default_factory=dict)
    facts: dict = field(default_factory=dict)

    def t(self, en, sv=None) -> str:
        opts = sv if (self.lang == "sv" and sv is not None) else en
        text = self.rng.choice(opts) if isinstance(opts, list) else opts
        return text.format(**self.v)


@dataclass
class Scenario:
    key: str
    topic: str
    theme: str
    journey_step: str
    lob: str
    daily_rate: float
    profile: Callable[[date, Timeline], float]
    dialogue: Callable[[Ctx], list[tuple[str, str]]]
    talk_mean_sec: int
    csat_mean: float
    resolved_prob: float
    repeat_prob_unresolved: float
    churn_prob: float
    transfer_prob: float
    self_service_prob: float
    chat_share: float
    failure_demand: bool
    sentiment_base: float
    trigger: str
    root_cause: str
    resolution: str
    problem_statement: str
    recommended_action: str
    owner: str
    expected_impact: str
    description: str
    bot_phrase: tuple[str, str]
    languages: tuple[str, ...] = ("en",)
    bot_only_prob: float = 0.0
    bot_dialogue: Callable[[Ctx], list[tuple[str, str]]] | None = None
    churn_intent_prob: float = 0.0
    customer_pool: str = "mobile"
    area: str = "General"


# ---------------------------------------------------------------------------
# Dialogue builders. Each returns the body of the conversation (opening and
# closing are added generically). They may write ground-truth details to c.facts.
# ---------------------------------------------------------------------------

def dlg_price_plan(c: Ctx) -> list[tuple[str, str]]:
    r = c.rng
    old_data, new_data = r.choice([(10, 25), (15, 30), (8, 25)])
    c.v.update(
        increase=r.choice([39, 49, 59]),
        old_plan=r.choice(["Mobil Bas", "Fastpris Classic", "Smart Start"]) + f" {old_data} GB",
        new_plan=f"Mobil Plus {new_data} GB",
        old_data=old_data,
        new_data=new_data,
        discount=r.choice([30, 40, 50]),
        alt_plan=f"Mobil Flex {old_data + 5} GB",
        tenure_years=max(2, c.customer.tenure_months(c.contact_date) // 12),
        email_date=fmt_date(c.tl.migration_email, c.lang),
    )
    turns = [("Customer", c.t(
        ["Hi, I got an email saying my subscription is being moved to a new price plan and that it will cost {increase} kronor more per month. I never asked for any change.",
         "I'm calling about the email you sent on {email_date} about migrating my plan. It says {old_plan} is being discontinued and I don't understand what I'm getting for the extra {increase} kronor.",
         "Yes hi, I received a message that my price plan changes from next month. Why should I pay {increase} kronor more when nothing is different for me?"],
        ["Hej, jag fick ett mejl om att mitt abonnemang flyttas till en ny prisplan och att det blir {increase} kronor dyrare i månaden. Jag har aldrig bett om någon ändring.",
         "Jag ringer om mejlet ni skickade den {email_date} om att mitt abonnemang ska migreras. Det står att {old_plan} läggs ner och jag förstår inte vad jag får för de extra {increase} kronorna."]))]
    if c.followup:
        turns.append(("Customer", c.t(
            "I called about this a few days ago and was told someone would get back to me, but nothing happened.",
            "Jag ringde om det här för några dagar sedan och fick höra att någon skulle återkomma, men inget har hänt.")))
    if c.self_service:
        turns.append(("Customer", c.t(
            "I tried to find more information on My Pages but it only says 'your plan is changing' without any details.",
            "Jag försökte hitta mer information på Mina sidor men där står bara 'ditt abonnemang ändras' utan några detaljer.")))
    turns += [
        ("Agent", c.t(
            "I understand. We're retiring some older plans, and {old_plan} is being migrated to {new_plan}. The new plan includes {new_data} GB instead of {old_data} GB, and free roaming in the Nordics.",
            "Jag förstår. Vi fasar ut några äldre abonnemang och {old_plan} flyttas till {new_plan}. Det nya abonnemanget har {new_data} GB i stället för {old_data} GB och fri roaming i Norden.")),
        ("Customer", c.t(
            "But I don't need more data. I've been a customer for {tenure_years} years and this feels like a price increase dressed up as an upgrade.",
            "Men jag behöver inte mer surf. Jag har varit kund i {tenure_years} år och det här känns som en prishöjning förklädd till en uppgradering.")),
    ]
    if c.churn_intent:
        turns.append(("Customer", c.t(
            "{competitor} offered me {competitor_offer}. Give me one reason not to switch.",
            "{competitor} har erbjudit mig {competitor_offer_sv}. Ge mig en anledning att inte byta.")))
    if c.resolved:
        turns += [
            ("Agent", c.t(
                "I can see that. I can put you on {alt_plan}, which is closer to what you have today, and give you {discount} kronor off per month for six months.",
                "Det förstår jag. Jag kan flytta dig till {alt_plan}, som ligger närmare det du har i dag, och ge dig {discount} kronor rabatt i månaden i sex månader.")),
            ("Customer", c.t(
                "Okay, that works. But the email should have explained this properly.",
                "Okej, det fungerar. Men mejlet borde ha förklarat det här ordentligt.")),
        ]
        c.facts["resolution"] = "Moved customer to a cheaper alternative plan with a temporary discount"
    else:
        turns += [
            ("Agent", c.t(
                "I'm sorry, I can't stop the migration, but I've noted your feedback. You can change plan on My Pages after the migration.",
                "Tyvärr kan jag inte stoppa migreringen, men jag har noterat dina synpunkter. Du kan byta abonnemang på Mina sidor efter migreringen.")),
            ("Customer", c.t(
                "That's not good enough. I'll have to think about whether I stay.",
                "Det räcker inte. Jag får fundera på om jag stannar kvar.")),
        ]
        c.facts["resolution"] = "Explained the migration; no alternative offered"
    return turns


def dlg_router_wifi(c: Ctx) -> list[tuple[str, str]]:
    r = c.rng
    known = c.contact_date >= c.tl.firmware_known
    push = c.tl.firmware_push
    c.v.update(
        minutes=r.choice([20, 30, 45]),
        push_weekday=fmt_weekday(push + timedelta(days=1), c.lang),
        update_date=fmt_date(push, c.lang),
    )
    c.facts["hardware_model"] = "Nova X3"
    turns = [("Customer", c.t(
        ["My Wi-Fi keeps dropping. Every {minutes} minutes or so all devices lose the connection and then it comes back. It started on {push_weekday} after the router restarted by itself during the night.",
         "Since a few days back the wireless network disappears all the time. Everything at home loses connection, but the cable to my computer still works.",
         "Hi, the internet keeps cutting out at home. I work from home and I've been kicked out of my Teams meetings several times this week."],
        ["Mitt wifi försvinner hela tiden. Ungefär var {minutes}:e minut tappar alla enheter anslutningen och sedan kommer den tillbaka. Det började i {push_weekday} efter att routern startat om sig själv på natten.",
         "Sedan några dagar tillbaka försvinner det trådlösa nätverket hela tiden. Allt hemma tappar uppkopplingen, men kabeln till datorn fungerar.",
         "Hej, internet bryts hela tiden hemma. Jag jobbar hemifrån och har blivit utkastad från Teams-möten flera gånger den här veckan."]))]
    if c.followup:
        c.v["prev_date"] = fmt_date(c.prev_date, c.lang)
        turns.append(("Customer", c.t(
            "I called on {prev_date} about this. I restarted the router like I was told but it is still happening.",
            "Jag ringde den {prev_date} om det här. Jag startade om routern som jag blev tillsagd men det händer fortfarande.")))
    if c.self_service:
        turns.append(("Customer", c.t(
            "I've already restarted it several times and followed the troubleshooting guide in the app.",
            "Jag har redan startat om den flera gånger och följt felsökningsguiden i appen.")))
    turns += [
        ("Agent", c.t("Which router do you have? The model is on the label underneath.",
                      "Vilken router har du? Modellen står på etiketten under.")),
        ("Customer", c.t("It says Nova X3.", "Det står Nova X3.")),
    ]
    if known:
        turns += [
            ("Agent", c.t(
                "Thank you. I can see your router was automatically updated to firmware 4.2.1 on {update_date}. We have several similar reports after that update and our technicians are working on a fix.",
                "Tack. Jag ser att din router automatiskt uppdaterades till firmware 4.2.1 den {update_date}. Vi har flera liknande ärenden efter den uppdateringen och våra tekniker jobbar på en lösning.")),
            ("Agent", c.t(
                "As a workaround you can turn off 'Smart Connect' in the router settings so that 2.4 and 5 GHz become separate networks. That has helped other customers.",
                "Som tillfällig lösning kan du stänga av 'Smart Connect' i routerns inställningar så att 2,4 och 5 GHz blir separata nätverk. Det har hjälpt andra kunder.")),
        ]
        if c.resolved:
            turns.append(("Customer", c.t(
                "Okay, I turned it off now and it looks stable. Please let me know when the real fix comes.",
                "Okej, nu har jag stängt av det och det verkar stabilt. Hör av er när den riktiga lösningen kommer.")))
            c.facts["resolution"] = "Workaround: disabled Smart Connect; permanent firmware fix pending"
        else:
            turns += [
                ("Customer", c.t(
                    "I already tried that setting. I need this to actually work, I'm paying for it.",
                    "Den inställningen har jag redan testat. Jag behöver att det faktiskt fungerar, jag betalar för det.")),
                ("Agent", c.t("I understand. I'll book a replacement router for you and escalate the case.",
                              "Jag förstår. Jag bokar en ersättningsrouter åt dig och eskalerar ärendet.")),
            ]
            c.facts["resolution"] = "Replacement router booked and case escalated"
    else:
        c.facts["root_cause"] = "Unknown at time of contact; no line fault found (router recently restarted)"
        turns += [
            ("Agent", c.t("Thank you. I can't see any faults on the line from here, the connection to the router looks fine.",
                          "Tack. Jag ser inga fel på linjen härifrån, anslutningen till routern ser bra ut.")),
            ("Agent", c.t("Let's try a factory reset. Press the reset button for ten seconds and wait until the lights turn white.",
                          "Vi testar en fabriksåterställning. Håll in reset-knappen i tio sekunder och vänta tills lamporna lyser vitt.")),
            ("Customer", c.t("Okay... it's restarting now.", "Okej... nu startar den om.")),
        ]
        if c.resolved:
            turns.append(("Customer", c.t("It seems to work now, thanks.", "Det verkar fungera nu, tack.")))
        else:
            turns += [
                ("Agent", c.t("If the problem comes back, please contact us again.",
                              "Om problemet kommer tillbaka får du gärna kontakta oss igen.")),
                ("Customer", c.t("This is the third evening in a row. I really hope it's fixed now.",
                                 "Det är tredje kvällen i rad. Jag hoppas verkligen att det är löst nu.")),
            ]
        c.facts["resolution"] = "Factory reset of router"
    return turns


def dlg_number_porting(c: Ctx) -> list[tuple[str, str]]:
    r = c.rng
    c.v["days"] = r.randint(3, 9)
    turns = [("Customer", c.t(
        ["I'm trying to bring my number over from {competitor}. I filled in the porting form on your website {days} days ago and nothing has happened.",
         "Hi, I got a message that my number transfer failed, but it doesn't say why. I'm moving from {competitor}.",
         "My new SIM card works but I still have a temporary number. The porting of my old number from {competitor} hasn't gone through."],
        ["Jag försöker flytta mitt nummer från {competitor}. Jag fyllde i flyttformuläret på er webb för {days} dagar sedan och inget har hänt.",
         "Hej, jag fick ett meddelande om att nummerflytten misslyckades men det står inte varför. Jag byter från {competitor}."]))]
    if c.self_service:
        turns.append(("Customer", c.t(
            "I tried to fix it myself on the website, but it just says 'porting rejected – contact customer service'.",
            "Jag försökte lösa det själv på webben men där står bara 'flytt avvisad – kontakta kundservice'.")))
    if c.followup:
        turns.append(("Customer", c.t(
            "This is the second time I'm contacting you about this. Last time I was told it would be done in three days.",
            "Det är andra gången jag kontaktar er om det här. Förra gången sa ni att det skulle vara klart på tre dagar.")))
    reason = r.randrange(3)
    turns.append(("Agent", c.t(
        ["I can see the porting request was rejected because the personal identity number didn't match the owner of the number at {competitor}.",
         "I can see the request was rejected because the porting date was set before your contract with {competitor} ends.",
         "The request is stuck because the SIM card number entered in the form was incomplete."][reason],
        ["Jag ser att flyttbegäran avvisades eftersom personnumret inte matchade ägaren till numret hos {competitor}.",
         "Jag ser att begäran avvisades eftersom flyttdatumet var satt innan ditt avtal hos {competitor} löper ut.",
         "Begäran har fastnat eftersom SIM-kortsnumret i formuläret var ofullständigt."][reason])))
    c.facts["root_cause"] = [
        "Porting rejected: identity number did not match number owner at donor operator",
        "Porting rejected: porting date before donor contract end",
        "Porting stuck: incomplete SIM card number in web form",
    ][reason]
    turns.append(("Customer", c.t(
        "Why doesn't the website tell me that? I could have fixed it myself.",
        "Varför står det inte det på webben? Då hade jag kunnat fixa det själv.")))
    if c.resolved:
        turns += [
            ("Agent", c.t("I've corrected it and submitted a new request. The number will be moved within 3 to 5 working days.",
                          "Jag har rättat det och skickat in en ny begäran. Numret flyttas inom 3 till 5 arbetsdagar.")),
            ("Customer", c.t("Okay, thanks.", "Okej, tack.")),
        ]
        c.facts["resolution"] = "Corrected porting data and resubmitted request"
    else:
        turns += [
            ("Agent", c.t("I need to escalate this to our porting team. They will contact you within 48 hours.",
                          "Jag behöver eskalera det här till vårt nummerflyttsteam. De kontaktar dig inom 48 timmar.")),
            ("Customer", c.t("Fine, but this is taking far too long.", "Okej, men det här tar alldeles för lång tid.")),
        ]
        c.facts["resolution"] = "Escalated to porting team"
    return turns


def dlg_invoice_higher(c: Ctx) -> list[tuple[str, str]]:
    r = c.rng
    normal = r.choice([299, 349, 399, 449])
    diff = r.choice([89, 120, 175, 240, 310])
    c.v.update(normal=normal, amount=normal + diff, diff=diff,
               country=r.choice(["Turkey", "Switzerland", "the USA", "Thailand"]),
               country_sv=r.choice(["Turkiet", "Schweiz", "USA", "Thailand"]))
    cause = r.randrange(4)
    turns = [("Customer", c.t(
        ["My invoice this month is {amount} kronor, normally it's around {normal}. Why is it so much higher?",
         "I don't understand my latest invoice. It's {diff} kronor more than usual.",
         "Hi, I'd like to know why my bill went up to {amount} kronor this month."],
        ["Min faktura den här månaden är på {amount} kronor, normalt brukar den ligga runt {normal}. Varför är den så mycket högre?",
         "Jag förstår inte min senaste faktura. Den är {diff} kronor högre än vanligt."]))]
    if c.self_service:
        turns.append(("Customer", c.t(
            "I checked the invoice in the app but the specification doesn't show what the extra cost is.",
            "Jag kollade fakturan i appen men specifikationen visar inte vad den extra kostnaden är.")))
    turns.append(("Agent", c.t(
        ["Let me have a look... You used mobile data in {country} on your trip, outside the EU, and that is charged per megabyte.",
         "Let me have a look... You bought two extra data packages of 5 GB during the month.",
         "Let me have a look... You changed plan in the middle of the month, so this invoice includes part of both plans.",
         "Let me have a look... Your device insurance started this month, that's 89 kronor, plus the first month is charged in advance."][cause],
        ["Jag ska titta... Du har surfat i {country_sv} under resan, utanför EU, och det debiteras per megabyte.",
         "Jag ska titta... Du har köpt två extra surfpaket på 5 GB under månaden.",
         "Jag ska titta... Du bytte abonnemang mitt i månaden, så fakturan innehåller delar av båda abonnemangen.",
         "Jag ska titta... Din mobilförsäkring började den här månaden, och första månaden debiteras i förskott."][cause])))
    c.facts["root_cause"] = [
        "Roaming data charges outside the EU",
        "Extra data packages purchased during the month",
        "Mid-month plan change causing overlapping charges",
        "New device insurance charged in advance",
    ][cause]
    c.facts["trigger_event"] = "Received invoice higher than usual"
    if c.resolved:
        turns.append(("Customer", c.t("Ah, okay. That explains it, thanks.", "Jaha, okej. Då förstår jag, tack.")))
        c.facts["resolution"] = "Explained invoice line items"
    else:
        turns += [
            ("Customer", c.t("I was never informed about that. I want it removed.",
                             "Det har jag aldrig blivit informerad om. Jag vill att det tas bort.")),
            ("Agent", c.t("I can't remove the charge, but I can split the payment into two invoices.",
                          "Jag kan inte ta bort avgiften, men jag kan dela upp betalningen på två fakturor.")),
            ("Customer", c.t("Hmm. Okay, I suppose.", "Hmm. Okej då.")),
        ]
        c.facts["resolution"] = "Explained charge and offered split payment; customer disputes charge"
    return turns


def dlg_final_invoice(c: Ctx) -> list[tuple[str, str]]:
    r = c.rng
    c.v.update(amount=r.choice([249, 412, 1180, 1960]), months=r.choice([4, 7, 11]))
    cause = r.randrange(2)
    turns = [
        ("Customer", c.t(["I cancelled my subscription last month and now I've received a final invoice of {amount} kronor. What is it for?",
                          "Hi, I got a final invoice after I ended my contract and I don't understand the amount, {amount} kronor."])),
        ("Agent", c.t(["The final invoice covers your last month, because we invoice in arrears.",
                       "It includes the remaining {months} instalments for the phone you bought on a payment plan."][cause])),
    ]
    c.facts["root_cause"] = ["Final period invoiced in arrears", "Remaining device instalments on final invoice"][cause]
    c.facts["trigger_event"] = "Received final invoice after cancellation"
    if c.resolved:
        turns += [
            ("Customer", c.t("Okay, I didn't know that. Can I pay it in parts?")),
            ("Agent", c.t("Yes, I've split it into three payments for you.")),
            ("Customer", c.t("Great, thanks for explaining it so clearly.")),
        ]
        c.facts["resolution"] = "Explained final invoice and split into instalments"
    else:
        turns += [("Customer", c.t("Nobody told me that when I cancelled. This is really disappointing."))]
        c.facts["resolution"] = "Explained final invoice"
    return turns


def dlg_delivery(c: Ctx) -> list[tuple[str, str]]:
    r = c.rng
    op = c.customer.network_operator or r.choice(NETWORKS)
    c.v.update(weeks=r.randint(2, 5), operator=op)
    c.facts["network_operator"] = op
    c.facts["root_cause"] = f"Installation backlog at network operator {op}; no proactive status updates"
    turns = [("Customer", c.t(["I ordered fiber broadband {weeks} weeks ago and I still don't have an installation date.",
                               "Hi, I'm calling about my broadband order. The confirmation said two weeks and it's been {weeks} weeks now.",
                               "The router arrived last week but nobody has come to install the fiber."]))]
    if c.followup:
        turns.append(("Customer", c.t("I've called about this before and was promised someone would call me back with a date.")))
    if c.self_service:
        turns.append(("Customer", c.t("The order tracking page has said 'in progress' since the day I ordered.")))
    turns += [
        ("Agent", c.t("I can see your address is in the {operator} network, and the installation is done by their technicians. Your order is waiting for a confirmed date from {operator}.")),
        ("Customer", c.t("Nobody told me that a different company does the installation.")),
    ]
    if c.resolved:
        turns += [("Agent", c.t("I've escalated it with {operator} and you will get an SMS with the installation date within two working days.")),
                  ("Customer", c.t("Okay, thank you."))]
        c.facts["resolution"] = f"Escalated installation date with {op}"
    else:
        turns += [("Agent", c.t("Unfortunately I can't give you a date until {operator} confirms it.")),
                  ("Customer", c.t("So I just have to wait without internet? I'm not happy with this."))]
        c.facts["resolution"] = "No installation date available; waiting for network operator"
    return turns


def dlg_activation(c: Ctx) -> list[tuple[str, str]]:
    op = c.customer.network_operator or c.rng.choice(NETWORKS)
    c.v.update(operator=op)
    c.facts["network_operator"] = op
    turns = [("Customer", c.t(["The technician installed the fiber box yesterday but I still have no internet.",
                               "Everything is connected but the light on the router is red and the internet doesn't work."]))]
    if c.self_service:
        turns.append(("Customer", c.t("I've restarted everything and checked the cables like the guide on your website says.")))
    turns.append(("Agent", c.t("Thanks. I can see that the port in the {operator} network hasn't been activated yet.")))
    if c.resolved:
        turns += [("Agent", c.t("I've sent an activation request, it should start working within an hour.")),
                  ("Customer", c.t("Great, thanks."))]
        c.facts["resolution"] = "Sent port activation request to network operator"
    else:
        turns += [("Agent", c.t("{operator} needs to send a technician again, I've booked that for you.")),
                  ("Customer", c.t("Again? I took a day off work for the first visit."))]
        c.facts["resolution"] = "New technician visit booked"
    return turns


def dlg_roaming(c: Ctx) -> list[tuple[str, str]]:
    r = c.rng
    c.v.update(country=r.choice(["Spain", "Italy", "Greece", "Croatia", "France"]), eu_gb=r.choice([14, 18, 22]))
    variant = r.randrange(2)
    if variant == 0:
        turns = [("Customer", c.t("I'm in {country} on holiday and my mobile data isn't working at all.")),
                 ("Agent", c.t("Can you check that data roaming is switched on in your phone's settings?"))]
        if c.self_service:
            turns.insert(1, ("Customer", c.t("I looked in the app but couldn't find any roaming settings.")))
        turns.append(("Customer", c.t("Oh, it was switched off. Now it works!") if c.resolved
                      else c.t("It's on, and it still doesn't work.")))
        c.facts["root_cause"] = "Data roaming disabled in device settings" if c.resolved else "Roaming data not working, cause unknown"
        c.facts["resolution"] = "Guided customer to enable data roaming" if c.resolved else "Reset network registration; issue persists"
    else:
        turns = [("Customer", c.t("I just got a text saying I've used up my roaming data in {country}. I've barely used anything.")),
                 ("Agent", c.t("In the EU you can use {eu_gb} GB of your data allowance. You've reached that, but I can add a 5 GB roaming package for 59 kronor."))]
        turns.append(("Customer", c.t("Okay, add it please.") if c.resolved else c.t("That's ridiculous, I don't want to pay extra.")))
        c.facts["root_cause"] = "EU fair-use roaming allowance reached"
        c.facts["resolution"] = "Added roaming data package" if c.resolved else "Explained EU roaming allowance"
    c.facts["trigger_event"] = "Travelling abroad"
    return turns


def dlg_esim(c: Ctx) -> list[tuple[str, str]]:
    turns = [("Customer", c.t(["I bought a new iPhone and want to move my number to an eSIM. The QR code from the app doesn't work.",
                               "I'm trying to activate eSIM on my new phone but it says 'eSIM cannot be added'."]))]
    if c.self_service:
        turns.append(("Customer", c.t("I followed the steps in the app twice.")))
    turns.append(("Agent", c.t("I'll generate a new eSIM profile for you. You'll get a new QR code by email in a few minutes.")))
    if c.resolved:
        turns.append(("Customer", c.t("Got it... it's activating now. Yes, it works!")))
        c.facts["resolution"] = "Generated new eSIM profile"
    else:
        turns += [("Customer", c.t("It still says it can't be added.")),
                  ("Agent", c.t("Then please visit one of our stores and they'll help you set it up."))]
        c.facts["resolution"] = "Referred customer to store"
    c.facts["trigger_event"] = "Bought a new phone"
    return turns


def dlg_app_bankid(c: Ctx) -> list[tuple[str, str]]:
    a, b = c.tl.bankid_incident
    incident = a <= c.contact_date <= b
    c.v.update(amount=c.rng.choice([299, 349, 449]), due=c.rng.choice([25, 27, 28]))
    turns = [("Customer", c.t(["I can't log in to the app with BankID. It just spins and then says 'something went wrong'.",
                               "Your app won't let me log in. BankID opens, I confirm, and then I'm back at the login page."]))]
    if incident:
        turns.append(("Agent", c.t("Thanks. We're aware of a login issue in app version 8.4 on Android. A fix is on its way; in the meantime you can log in on My Pages in your browser.")))
        c.facts.update(root_cause="Login bug in app version 8.4 on Android", trigger_event="App update to version 8.4")
    else:
        turns.append(("Agent", c.t("It looks like your BankID app needs to be updated. Can you update it and try again?")))
        c.facts.update(root_cause="Outdated BankID app on customer device", trigger_event="Attempted login in the app")
    turns += [("Agent", c.t("What did you want to do in the app? I can help you here.")),
              ("Customer", c.t("I just wanted to check my invoice.")),
              ("Agent", c.t("Your invoice is {amount} kronor and it's due on the {due}th."))]
    if not c.resolved:
        turns.append(("Customer", c.t("Okay, but I need the app to work, I don't want to call every time.")))
    c.facts["resolution"] = "Provided invoice information and login workaround"
    return turns


def dlg_churn(c: Ctx) -> list[tuple[str, str]]:
    r = c.rng
    c.v.update(retention=r.choice([50, 75, 100]), end_date=fmt_date(c.contact_date + timedelta(days=30), c.lang))
    reason = r.randrange(3)
    turns = [("Customer", c.t(
        ["I want to cancel my subscription. {competitor} has offered me {competitor_offer} and I can't justify paying more here.",
         "Hi, I'd like to terminate my contract. I'm moving to {competitor}, they gave me {competitor_offer}."],
        ["Jag vill säga upp mitt abonnemang. {competitor} har erbjudit mig {competitor_offer_sv} och jag kan inte motivera att betala mer här.",
         "Hej, jag vill avsluta mitt avtal. Jag går över till {competitor}, de gav mig {competitor_offer_sv}."])),
        ("Agent", c.t("I'm sorry to hear that. May I ask what the main reason is?",
                      "Vad tråkigt att höra. Får jag fråga vad som är den främsta anledningen?")),
        ("Customer", c.t(
            ["It's mainly the price.",
             "I've had to call about wrong invoices three times this year, I'm tired of it.",
             "The coverage at my summer house is bad, and now this offer came along."][reason],
            ["Det är främst priset.",
             "Jag har fått ringa om felaktiga fakturor tre gånger i år, jag är trött på det.",
             "Täckningen vid mitt sommarhus är dålig, och nu kom det här erbjudandet."][reason])),
        ("Agent", c.t("I can offer you {retention} kronor off per month for 12 months if you stay with us.",
                      "Jag kan erbjuda dig {retention} kronor rabatt i månaden i 12 månader om du stannar hos oss.")),
    ]
    c.facts["root_cause"] = ["Price gap versus competitor offer", "Repeated billing errors", "Poor coverage at secondary location"][reason]
    c.facts["trigger_event"] = "Received competitor offer"
    if c.resolved:
        turns.append(("Customer", c.t("Okay, that's actually better. I'll stay.", "Okej, det är faktiskt bättre. Då stannar jag.")))
        c.facts["resolution"] = "Retention discount accepted"
    else:
        turns += [
            ("Customer", c.t("Thanks, but I've decided. Please go ahead with the cancellation.",
                             "Tack, men jag har bestämt mig. Genomför uppsägningen.")),
            ("Agent", c.t("Understood. Your subscription will end on {end_date}.",
                          "Uppfattat. Ditt abonnemang avslutas den {end_date}.")),
        ]
        c.facts["resolution"] = "Cancellation processed; retention offer declined"
    return turns


def dlg_puk_agent(c: Ctx) -> list[tuple[str, str]]:
    c.facts["resolution"] = "Agent verified customer manually and sent PUK code"
    c.facts["root_cause"] = "Voicebot verification failed because BankID is on the locked phone"
    return [("Customer", c.t("I need my PUK code but the voicebot couldn't verify me because my BankID is on the locked phone.",
                             "Jag behöver min PUK-kod men röstroboten kunde inte verifiera mig eftersom mitt BankID ligger i den låsta telefonen.")),
            ("Agent", c.t("No problem, I'll verify you with a few questions instead and send the code by SMS to your other number.",
                          "Inga problem, jag verifierar dig med några frågor i stället och skickar koden via SMS till ditt andra nummer.")),
            ("Customer", c.t("Perfect, thank you.", "Perfekt, tack."))]


def dlg_puk_bot(c: Ctx) -> list[tuple[str, str]]:
    c.facts["resolution"] = "Voicebot verified with BankID and sent PUK code"
    c.facts["root_cause"] = "SIM locked after wrong PIN attempts"
    return [("Bot", c.t("Hi, I'm the virtual assistant. Tell me in a few words what you need help with.",
                        "Hej, jag är den virtuella assistenten. Berätta med några ord vad du behöver hjälp med.")),
            ("Customer", c.t("I need my PUK code, my phone is locked.", "Jag behöver min PUK-kod, telefonen är låst.")),
            ("Bot", c.t("I can help with that. To verify you, please confirm with BankID.",
                        "Det kan jag hjälpa till med. Bekräfta med BankID så att jag kan verifiera dig.")),
            ("Customer", c.t("Done.", "Klart.")),
            ("Bot", c.t("Thank you. Your PUK code has been sent by SMS to your registered contact number. Is there anything else?",
                        "Tack. Din PUK-kod har skickats via SMS till ditt registrerade kontaktnummer. Var det något mer?")),
            ("Customer", c.t("No, thanks.", "Nej, tack."))]


def dlg_upgrade(c: Ctx) -> list[tuple[str, str]]:
    r = c.rng
    c.v.update(phone=r.choice(["iPhone 18", "Galaxy S26", "Pixel 11"]), price=r.choice([429, 489, 549]))
    turns = [("Customer", c.t(["Hi, am I eligible to upgrade my phone? I've had this one for two years.",
                               "I'm thinking about getting the new {phone}. What would it cost me?"])),
             ("Agent", c.t("Your current instalment plan is fully paid, so you can upgrade. The {phone} is {price} kronor a month over 24 months with your current plan."))]
    if c.resolved:
        turns += [("Customer", c.t("Sounds good, let's do it.")),
                  ("Agent", c.t("Great, I've placed the order. It will be delivered in one to two days."))]
        c.facts["resolution"] = "Phone upgrade sold"
    else:
        turns.append(("Customer", c.t("I'll think about it, thanks.")))
        c.facts["resolution"] = "Upgrade offer presented; no purchase"
    c.facts["trigger_event"] = "New phone launch / end of instalment plan"
    c.facts["root_cause"] = ""
    return turns


def dlg_tv(c: Ctx) -> list[tuple[str, str]]:
    r = c.rng
    c.v.update(channel=r.choice(["TV4 Sport", "Discovery", "Eurosport 1"]), date=fmt_date(c.contact_date - timedelta(days=r.randint(3, 12)), "en"))
    turns = [("Customer", c.t("Some channels in my TV package have disappeared. I can't watch {channel} anymore.")),
             ("Agent", c.t("The channel line-up changed on {date}, and {channel} moved to the Plus package. We sent information about it by email."))]
    if c.resolved:
        turns += [("Customer", c.t("I never saw that email. Can I get Plus for the same price for a while?")),
                  ("Agent", c.t("I can give you Plus free for three months.")),
                  ("Customer", c.t("Okay, thanks."))]
        c.facts["resolution"] = "Three months of Plus package for free"
    else:
        turns.append(("Customer", c.t("Then I want to cancel the TV package. I'm not paying more for the same thing.")))
        c.facts["resolution"] = "Explained channel package change"
    return turns


def dlg_payment_ext_agent(c: Ctx) -> list[tuple[str, str]]:
    c.v["new_due"] = fmt_date(c.contact_date + timedelta(days=14), c.lang)
    c.facts["resolution"] = "Invoice due date extended by 14 days"
    return [("Customer", c.t("I can't pay my invoice by the due date. Can I get an extension?",
                             "Jag kan inte betala fakturan i tid. Kan jag få anstånd?")),
            ("Agent", c.t("Of course. I've moved the due date to {new_due}. There is no extra fee.",
                          "Självklart. Jag har flyttat förfallodagen till {new_due}. Det kostar inget extra.")),
            ("Customer", c.t("Thank you so much.", "Tack så mycket."))]


def dlg_payment_ext_bot(c: Ctx) -> list[tuple[str, str]]:
    c.v["new_due"] = fmt_date(c.contact_date + timedelta(days=14), c.lang)
    c.facts["resolution"] = "Voicebot extended invoice due date by 14 days"
    return [("Bot", c.t("Hi, I'm the virtual assistant. Tell me in a few words what you need help with.",
                        "Hej, jag är den virtuella assistenten. Berätta med några ord vad du behöver hjälp med.")),
            ("Customer", c.t("I need a few more days to pay my invoice.", "Jag behöver några dagar till för att betala fakturan.")),
            ("Bot", c.t("I can move the due date by up to 14 days. Do you want to move it to {new_due}?",
                        "Jag kan flytta förfallodagen upp till 14 dagar. Vill du flytta den till {new_due}?")),
            ("Customer", c.t("Yes.", "Ja.")),
            ("Bot", c.t("Done. Your new due date is {new_due}.", "Klart. Din nya förfallodag är {new_due}."))]


# ---------------------------------------------------------------------------
# Time profiles (multiplier on daily_rate)
# ---------------------------------------------------------------------------

def flat(_d: date, _tl: Timeline) -> float:
    return 1.0


def migration_profile(d: date, tl: Timeline) -> float:
    days = (d - tl.migration_email).days
    return 0.0 if days < 0 else 0.15 + math.exp(-days / 9)


def firmware_profile(d: date, tl: Timeline) -> float:
    days = (d - tl.firmware_push).days
    return 0.0 if days < 1 else min(1.0, 0.12 + 0.08 * days)


def bankid_profile(d: date, tl: Timeline) -> float:
    a, b = tl.bankid_incident
    return 12.0 if a <= d <= b else 1.0


def roaming_profile(d: date, tl: Timeline) -> float:
    return 3.0 if d <= tl.summer_end else 1.0


def esim_profile(d: date, tl: Timeline) -> float:
    days = (d - tl.iphone_launch).days
    return 1.0 if days < 0 else 1.0 + 2.5 * math.exp(-days / 8)


def upgrade_profile(d: date, tl: Timeline) -> float:
    return 1.5 if d >= tl.iphone_launch else 1.0


SCENARIOS: list[Scenario] = [
    Scenario(
        key="price_plan_migration", topic="Price plan migration confusion", theme="Billing & pricing",
        journey_step="plan change & migration", lob="Mobile", daily_rate=24, profile=migration_profile,
        dialogue=dlg_price_plan, talk_mean_sec=540, csat_mean=2.6, resolved_prob=0.45, repeat_prob_unresolved=0.35,
        churn_prob=0.14, transfer_prob=0.08, self_service_prob=0.45, chat_share=0.2, failure_demand=True,
        sentiment_base=-0.45, churn_intent_prob=0.3, languages=("en", "sv"), customer_pool="long_mobile", area="Billing",
        trigger="Price plan migration email", root_cause="Unclear communication of legacy plan migration and price increase",
        resolution="Explained migration", description="Customers confused or upset by the email announcing migration of legacy plans to a more expensive plan.",
        problem_statement="Migration email for legacy mobile plans drives high-AHT, low-CSAT calls from long-tenure customers, with churn threats.",
        recommended_action="Rewrite the migration email with a clear price/value comparison, add a 'compare and choose' flow on My Pages, and pre-approve a retention alternative for 5+ year customers.",
        owner="Mobile B2C – Pricing & Communication", expected_impact="Reduce migration-related calls by 40-60% and protect long-tenure customers from churn.",
        bot_phrase=("A question about the price plan change email", "En fråga om mejlet om ändrad prisplan"),
    ),
    Scenario(
        key="router_firmware_wifi", topic="Wi-Fi drops after router firmware update", theme="Technical support – Fixed",
        journey_step="usage & technical support", lob="Fixed Broadband", daily_rate=24, profile=firmware_profile,
        dialogue=dlg_router_wifi, talk_mean_sec=720, csat_mean=2.4, resolved_prob=0.3, repeat_prob_unresolved=0.65,
        churn_prob=0.06, transfer_prob=0.3, self_service_prob=0.55, chat_share=0.15, failure_demand=True,
        sentiment_base=-0.5, churn_intent_prob=0.08, languages=("en", "sv"), customer_pool="x3", area="Tech",
        trigger="Automatic router firmware update 4.2.1", root_cause="Firmware 4.2.1 on Nova X3 routers causes Wi-Fi instability",
        resolution="Workaround or replacement router", description="Wi-Fi repeatedly disconnecting on Nova X3 routers after the automatic firmware 4.2.1 update.",
        problem_statement="Firmware 4.2.1 pushed to Nova X3 routers causes Wi-Fi drops; agents only recognised the pattern after several days, driving repeat contacts.",
        recommended_action="Roll back or hot-fix firmware 4.2.1, proactively SMS affected Nova X3 customers with the Smart Connect workaround, and add an IVR/known-issue message.",
        owner="Fixed Broadband – CPE & Network Operations", expected_impact="Eliminate a fast-growing failure-demand driver with ~2 contacts per affected customer.",
        bot_phrase=("My Wi-Fi keeps dropping", "Mitt wifi försvinner hela tiden"),
    ),
    Scenario(
        key="number_porting", topic="Number porting failed or delayed", theme="Onboarding & porting",
        journey_step="onboarding & activation", lob="Mobile", daily_rate=5, profile=flat,
        dialogue=dlg_number_porting, talk_mean_sec=420, csat_mean=3.0, resolved_prob=0.55, repeat_prob_unresolved=0.6,
        churn_prob=0.03, transfer_prob=0.1, self_service_prob=0.8, chat_share=0.6, failure_demand=True,
        sentiment_base=-0.3, languages=("en", "sv"), customer_pool="mobile", area="Sales",
        trigger="Failed number porting via web self-service", root_cause="Porting request rejected; web self-service shows no reason",
        resolution="Resubmitted porting request", description="New customers whose number porting from another operator failed or is delayed.",
        problem_statement="Web number-porting flow rejects requests without explaining why, so customers chat and then call again within a week.",
        recommended_action="Show the rejection reason and an inline fix in the porting flow; validate ID number and SIM number before submission.",
        owner="Mobile B2C – Onboarding Journey", expected_impact="Remove most repeat contacts in the porting journey and speed up activation.",
        bot_phrase=("My number porting doesn't work", "Min nummerflytt fungerar inte"),
    ),
    Scenario(
        key="invoice_higher", topic="Invoice higher than expected", theme="Billing & pricing",
        journey_step="billing & payment", lob="Mobile", daily_rate=9, profile=flat,
        dialogue=dlg_invoice_higher, talk_mean_sec=360, csat_mean=3.6, resolved_prob=0.75, repeat_prob_unresolved=0.25,
        churn_prob=0.02, transfer_prob=0.03, self_service_prob=0.35, chat_share=0.3, failure_demand=True,
        sentiment_base=-0.1, languages=("en", "sv"), customer_pool="mobile", area="Billing",
        trigger="Received invoice higher than usual", root_cause="Invoice specification does not explain extra charges",
        resolution="Explained invoice line items", description="Customers asking why their invoice is higher than usual.",
        problem_statement="Invoice specification in the app does not explain extra charges (roaming, top-ups, plan changes).",
        recommended_action="Add plain-language explanations of variable charges in the app invoice view and a push notice when roaming charges start.",
        owner="Billing – Invoice Experience", expected_impact="Steady, high-volume driver; good deflection candidate with low CSAT risk.",
        bot_phrase=("A question about my invoice", "En fråga om min faktura"),
    ),
    Scenario(
        key="final_invoice", topic="Final invoice after cancellation", theme="Billing & pricing",
        journey_step="termination & retention", lob="Mobile", daily_rate=2.5, profile=flat,
        dialogue=dlg_final_invoice, talk_mean_sec=330, csat_mean=4.2, resolved_prob=0.85, repeat_prob_unresolved=0.2,
        churn_prob=0.0, transfer_prob=0.02, self_service_prob=0.1, chat_share=0.2, failure_demand=True,
        sentiment_base=0.1, customer_pool="mobile", area="Billing",
        trigger="Received final invoice after cancellation", root_cause="Final invoice content not explained at cancellation",
        resolution="Explained final invoice", description="Former customers asking about the content of their final invoice.",
        problem_statement="Final invoice questions are frequent but have high CSAT when handled by an agent – a 'do not deflect' contact type.",
        recommended_action="Explain the final invoice in the cancellation confirmation, but keep agent access for this contact type (high CSAT sensitivity).",
        owner="Billing – Invoice Experience", expected_impact="Moderate volume reduction while protecting a high-CSAT moment.",
        bot_phrase=("A question about my final invoice", "En fråga om min slutfaktura"),
    ),
    Scenario(
        key="broadband_delivery", topic="Broadband installation delayed", theme="Orders & delivery",
        journey_step="delivery & installation", lob="Fixed Broadband", daily_rate=5, profile=flat,
        dialogue=dlg_delivery, talk_mean_sec=420, csat_mean=2.9, resolved_prob=0.5, repeat_prob_unresolved=0.5,
        churn_prob=0.05, transfer_prob=0.05, self_service_prob=0.4, chat_share=0.25, failure_demand=True,
        sentiment_base=-0.35, customer_pool="new_fixed", area="Delivery",
        trigger="Broadband order without installation date", root_cause="Installation backlog at network operator; no proactive status updates",
        resolution="Escalated with network operator", description="New broadband customers waiting for an installation date.",
        problem_statement="New fibre customers call repeatedly about missing installation dates, concentrated in the OpenNet Syd network.",
        recommended_action="Agree SLA and status feed with OpenNet Syd, and send proactive SMS updates with expected installation date.",
        owner="Fixed Broadband – Delivery & Partners", expected_impact="Reduce repeat delivery contacts from new customers and improve onboarding CSAT.",
        bot_phrase=("Where is my broadband installation", "När blir mitt bredband installerat"),
    ),
    Scenario(
        key="fiber_activation", topic="Broadband not working after installation", theme="Orders & delivery",
        journey_step="onboarding & activation", lob="Fixed Broadband", daily_rate=3, profile=flat,
        dialogue=dlg_activation, talk_mean_sec=480, csat_mean=3.1, resolved_prob=0.65, repeat_prob_unresolved=0.45,
        churn_prob=0.03, transfer_prob=0.2, self_service_prob=0.5, chat_share=0.2, failure_demand=True,
        sentiment_base=-0.25, customer_pool="new_fixed", area="Tech",
        trigger="Fibre installation completed", root_cause="Port in network operator not activated after installation",
        resolution="Sent activation request", description="Broadband not working right after installation because the port is not activated.",
        problem_statement="Ports are not activated after fibre installation, so new customers have no internet on day one.",
        recommended_action="Automate port activation on installation completion and add an activation check before the technician leaves.",
        owner="Fixed Broadband – Delivery & Partners", expected_impact="Fewer day-one failures for new customers.",
        bot_phrase=("My new broadband doesn't work", "Mitt nya bredband fungerar inte"),
    ),
    Scenario(
        key="roaming", topic="Mobile data not working abroad", theme="Technical support – Mobile",
        journey_step="usage & technical support", lob="Mobile", daily_rate=3, profile=roaming_profile,
        dialogue=dlg_roaming, talk_mean_sec=300, csat_mean=3.7, resolved_prob=0.7, repeat_prob_unresolved=0.2,
        churn_prob=0.01, transfer_prob=0.03, self_service_prob=0.3, chat_share=0.45, failure_demand=True,
        sentiment_base=-0.1, customer_pool="mobile", area="Tech",
        trigger="Travelling abroad", root_cause="Roaming settings or EU fair-use allowance",
        resolution="Roaming guidance", description="Mobile data issues while travelling abroad.",
        problem_statement="Summer roaming questions (settings, EU allowance) peak in July–August.",
        recommended_action="Send a pre-travel SMS with roaming settings and allowance, and surface roaming status in the app.",
        owner="Mobile B2C – Usage Experience", expected_impact="Seasonal deflection opportunity with low CSAT risk.",
        bot_phrase=("My data doesn't work abroad", "Min surf fungerar inte utomlands"),
    ),
    Scenario(
        key="esim", topic="eSIM activation problems", theme="Technical support – Mobile",
        journey_step="onboarding & activation", lob="Mobile", daily_rate=2.5, profile=esim_profile,
        dialogue=dlg_esim, talk_mean_sec=420, csat_mean=3.5, resolved_prob=0.75, repeat_prob_unresolved=0.3,
        churn_prob=0.01, transfer_prob=0.05, self_service_prob=0.7, chat_share=0.5, failure_demand=True,
        sentiment_base=-0.15, customer_pool="mobile", area="Tech",
        trigger="Bought a new phone", root_cause="eSIM QR code from the app is invalid or expired",
        resolution="Generated new eSIM profile", description="Customers unable to activate an eSIM on a new phone.",
        problem_statement="eSIM QR codes from the app fail, especially after new phone launches.",
        recommended_action="Fix QR code expiry in the app eSIM flow and add an in-app 'regenerate eSIM' button.",
        owner="Mobile B2C – Digital Channels", expected_impact="Deflect most eSIM contacts during launch peaks.",
        bot_phrase=("I can't activate my eSIM", "Jag kan inte aktivera mitt eSIM"),
    ),
    Scenario(
        key="app_bankid_login", topic="Cannot log in to app with BankID", theme="Digital self-service",
        journey_step="usage & technical support", lob="Mobile", daily_rate=1, profile=bankid_profile,
        dialogue=dlg_app_bankid, talk_mean_sec=300, csat_mean=3.3, resolved_prob=0.7, repeat_prob_unresolved=0.2,
        churn_prob=0.01, transfer_prob=0.02, self_service_prob=1.0, chat_share=0.3, failure_demand=True,
        sentiment_base=-0.2, customer_pool="bankid", area="Digital",
        trigger="Attempted login in the app", root_cause="Login bug in app version 8.4 on Android",
        resolution="Provided information and workaround", description="Customers unable to log in to the app using BankID.",
        problem_statement="App login failures force customers to call for simple information (e.g. invoice amount).",
        recommended_action="Add login-failure monitoring with automatic known-issue banners; staged app rollouts by region.",
        owner="Digital Channels – App", expected_impact="Faster detection of app incidents; avoid two-week call spikes.",
        bot_phrase=("I can't log in to the app", "Jag kan inte logga in i appen"),
    ),
    Scenario(
        key="churn_competitor", topic="Cancellation due to competitor offer", theme="Retention & churn",
        journey_step="termination & retention", lob="Mobile", daily_rate=4, profile=flat,
        dialogue=dlg_churn, talk_mean_sec=480, csat_mean=3.2, resolved_prob=0.4, repeat_prob_unresolved=0.05,
        churn_prob=0.85, transfer_prob=0.15, self_service_prob=0.0, chat_share=0.15, failure_demand=False,
        sentiment_base=-0.2, churn_intent_prob=1.0, languages=("en", "sv"), customer_pool="any", area="Retention",
        trigger="Received competitor offer", root_cause="Price gap versus competitor offer",
        resolution="Retention offer", description="Customers requesting cancellation, typically citing a competitor offer.",
        problem_statement="Competitor offers (Tre, Tele2, Comviq…) drive cancellations; billing errors are a recurring secondary reason.",
        recommended_action="Track competitor offers mentioned in calls weekly and adjust retention offers; flag customers with repeated billing contacts for proactive retention.",
        owner="Retention & Pricing", expected_impact="Higher save rate and earlier intervention for at-risk customers.",
        bot_phrase=("I want to cancel my subscription", "Jag vill säga upp mitt abonnemang"),
    ),
    Scenario(
        key="puk", topic="PUK code request", theme="Technical support – Mobile",
        journey_step="usage & technical support", lob="Mobile", daily_rate=4, profile=flat,
        dialogue=dlg_puk_agent, talk_mean_sec=150, csat_mean=4.3, resolved_prob=0.97, repeat_prob_unresolved=0.1,
        churn_prob=0.0, transfer_prob=0.0, self_service_prob=0.0, chat_share=0.0, failure_demand=False,
        sentiment_base=0.3, bot_only_prob=0.9, bot_dialogue=dlg_puk_bot, languages=("en", "sv"), customer_pool="mobile", area="General",
        trigger="SIM locked after wrong PIN attempts", root_cause="SIM locked after wrong PIN attempts",
        resolution="PUK code sent", description="Customers requesting their PUK code; mostly handled by the voicebot.",
        problem_statement="PUK requests are almost fully contained by the voicebot – an automation success.",
        recommended_action="Keep in voicebot; add a non-BankID verification path for customers whose BankID is on the locked phone.",
        owner="Customer Service – Automation", expected_impact="Remove the remaining agent-handled PUK contacts.",
        bot_phrase=("I need my PUK code", "Jag behöver min PUK-kod"),
    ),
    Scenario(
        key="device_upgrade", topic="Phone upgrade eligibility", theme="Sales & upgrades",
        journey_step="purchase", lob="Mobile", daily_rate=4, profile=upgrade_profile,
        dialogue=dlg_upgrade, talk_mean_sec=420, csat_mean=4.3, resolved_prob=0.4, repeat_prob_unresolved=0.05,
        churn_prob=0.0, transfer_prob=0.02, self_service_prob=0.0, chat_share=0.45, failure_demand=False,
        sentiment_base=0.4, customer_pool="mobile", area="Sales",
        trigger="New phone launch / end of instalment plan", root_cause="",
        resolution="Upgrade offer", description="Customers asking whether they can upgrade their phone (sales opportunity).",
        problem_statement="Upgrade-eligibility contacts are value demand with high CSAT and sales potential – do not deflect.",
        recommended_action="Route upgrade questions to sales-skilled agents/chat; send proactive eligibility offers when instalments end.",
        owner="Sales – Mobile Devices", expected_impact="Increase conversion on value-creating contacts.",
        bot_phrase=("Can I upgrade my phone", "Kan jag byta telefon"),
    ),
    Scenario(
        key="tv_channels", topic="TV channels missing from package", theme="TV",
        journey_step="plan change & migration", lob="TV", daily_rate=1.5, profile=flat,
        dialogue=dlg_tv, talk_mean_sec=360, csat_mean=3.0, resolved_prob=0.6, repeat_prob_unresolved=0.15,
        churn_prob=0.05, transfer_prob=0.03, self_service_prob=0.1, chat_share=0.2, failure_demand=True,
        sentiment_base=-0.25, customer_pool="tv", area="TV",
        trigger="TV channel line-up change", root_cause="Channel moved to a higher package; change not noticed by customer",
        resolution="Temporary Plus package", description="TV customers missing channels after a line-up change.",
        problem_statement="Channel line-up changes are not noticed by customers until channels disappear.",
        recommended_action="Show an on-screen notice on the TV box before line-up changes.",
        owner="TV – Content & Packaging", expected_impact="Small but avoidable contact driver.",
        bot_phrase=("Channels are missing on my TV", "Det saknas kanaler på min tv"),
    ),
    Scenario(
        key="payment_extension", topic="Payment extension request", theme="Billing & pricing",
        journey_step="billing & payment", lob="Mobile", daily_rate=3, profile=flat,
        dialogue=dlg_payment_ext_agent, talk_mean_sec=210, csat_mean=4.1, resolved_prob=0.95, repeat_prob_unresolved=0.1,
        churn_prob=0.01, transfer_prob=0.0, self_service_prob=0.0, chat_share=0.25, failure_demand=False,
        sentiment_base=0.2, bot_only_prob=0.35, bot_dialogue=dlg_payment_ext_bot, languages=("en", "sv"), customer_pool="any", area="Billing",
        trigger="Unable to pay invoice by due date", root_cause="Customer needs more time to pay",
        resolution="Due date extended", description="Customers asking to extend the invoice due date.",
        problem_statement="Payment extensions are simple and partly automated in the voicebot.",
        recommended_action="Increase voicebot/app containment for due-date extensions.",
        owner="Billing – Collections", expected_impact="Low-risk automation candidate.",
        bot_phrase=("I need to postpone my invoice", "Jag behöver skjuta upp min faktura"),
    ),
]
SCN = {s.key: s for s in SCENARIOS}

# Multi-intent snippets: (scenario key for ground truth, en customer, en agent, sv customer, sv agent)
SECONDARY_SNIPPETS = {
    "invoice_higher": ("While I have you – why was my last invoice higher than usual?",
                       "That's because you bought an extra data package during the month.",
                       "När jag ändå har dig – varför var min senaste faktura högre än vanligt?",
                       "Det beror på att du köpte ett extra surfpaket under månaden."),
    "price_plan_migration": ("One more thing, I got an email about a new price plan. Does that affect me?",
                             "Yes, your plan will be migrated next month. The price goes up a bit but you get more data.",
                             "En sak till, jag fick ett mejl om en ny prisplan. Påverkar det mig?",
                             "Ja, ditt abonnemang migreras nästa månad. Priset går upp lite men du får mer surf."),
    "esim": ("Also, how do I activate eSIM on my new phone?",
             "You can download the eSIM profile in the app under 'My subscription'.", None, None),
    "payment_extension": ("And can I get a few extra days to pay this month?",
                          "Yes, I've moved your due date by 14 days.",
                          "Och kan jag få några extra dagar att betala den här månaden?",
                          "Ja, jag har flyttat förfallodagen 14 dagar."),
    "device_upgrade": ("By the way, am I eligible for a new phone?",
                       "Yes, your instalment plan is paid off. I'll email you our current offers.", None, None),
}


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------

def poisson(rng: random.Random, lam: float) -> int:
    if lam <= 0:
        return 0
    if lam > 30:
        return max(0, round(rng.gauss(lam, math.sqrt(lam))))
    limit, k, p = math.exp(-lam), 0, 1.0
    while True:
        p *= rng.random()
        if p <= limit:
            return k
        k += 1


def stable_id(prefix: str, *parts) -> str:
    return prefix + hashlib.sha256("|".join(map(str, parts)).encode()).hexdigest()[:14]


def build_customers(rng: random.Random, n: int, tl: Timeline) -> list[Customer]:
    regions, weights = zip(*REGIONS.items())
    customers = []
    for i in range(n):
        is_new = rng.random() < 0.18
        if is_new:
            since = tl.start - timedelta(days=75) + timedelta(days=rng.randint(0, (tl.end - tl.start).days + 70))
            has_fixed, has_mobile = rng.random() < 0.7, rng.random() < 0.6
        else:
            years = rng.choices([0.5, 1.5, 3.5, 7, 14], weights=[20, 20, 25, 20, 15])[0]
            since = tl.start - timedelta(days=int(years * 365 * rng.uniform(0.7, 1.3)))
            has_fixed, has_mobile = rng.random() < 0.45, rng.random() < 0.88
        if not (has_fixed or has_mobile):
            has_mobile = True
        region = rng.choices(regions, weights=weights)[0]
        router = rng.choices(["Nova X3", "Nova X2", "Fiber Box F1"], weights=[40, 45, 15])[0] if has_fixed else None
        customers.append(Customer(
            key=stable_id("C", "cust", i),
            business_type="B2B" if rng.random() < 0.15 else "B2C",
            region=region,
            customer_since=since,
            has_mobile=has_mobile,
            has_fixed=has_fixed,
            has_tv=has_fixed and rng.random() < 0.45,
            router_model=router,
            network_operator=(NETWORK_BY_REGION.get(region) or rng.choice(NETWORKS)) if has_fixed else None,
        ))
    return customers


class CustomerPicker:
    def __init__(self, rng: random.Random, customers: list[Customer], tl: Timeline):
        self.rng, self.tl = rng, tl
        self.any = customers
        self.mobile = [c for c in customers if c.has_mobile]
        self.long_mobile = [c for c in self.mobile if c.business_type == "B2C" and (tl.start - c.customer_since).days > 5 * 365]
        self.fixed = [c for c in customers if c.has_fixed]
        self.x3 = [c for c in self.fixed if c.router_model == "Nova X3"]
        self.tv = [c for c in customers if c.has_tv]
        self.skane_mobile = [c for c in self.mobile if c.region == "Skåne"]

    def pick(self, pool: str, d: date) -> Customer:
        r = self.rng
        if pool == "long_mobile" and r.random() < 0.75:
            return r.choice(self.long_mobile)
        if pool == "x3":
            return r.choice(self.x3)
        if pool == "tv":
            return r.choice(self.tv)
        if pool == "bankid":
            a, b = self.tl.bankid_incident
            if a <= d <= b and r.random() < 0.7:
                return r.choice(self.skane_mobile)
            return r.choice(self.mobile)
        if pool == "new_fixed":
            cands = [c for c in self.fixed if 0 <= (d - c.customer_since).days <= 75]
            if cands:
                w = [3.0 if c.network_operator == "OpenNet Syd" else 1.0 for c in cands]
                return r.choices(cands, weights=w)[0]
            return r.choice(self.fixed)
        if pool == "any":
            return r.choice(self.any)
        return r.choice(self.mobile)


HOUR_WEIGHTS = {8: 6, 9: 10, 10: 11, 11: 10, 12: 8, 13: 9, 14: 9, 15: 8, 16: 7, 17: 6, 18: 5, 19: 4, 20: 2}


def random_local_ts(rng: random.Random, d: date) -> datetime:
    hours, w = zip(*HOUR_WEIGHTS.items())
    h = rng.choices(hours, weights=w)[0]
    return datetime.combine(d, time(h, rng.randint(0, 59), rng.randint(0, 59)), TZ)


def ts(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M:%S+00:00")


def opening(c: Ctx, voicebot_first: bool, bot_phrase: tuple[str, str]) -> list[tuple[str, str]]:
    turns = []
    if voicebot_first:
        turns += [("Bot", c.t("Hi, I'm the virtual assistant. In a few words, what are you calling about?",
                              "Hej, jag är den virtuella assistenten. Berätta med några ord vad du ringer om.")),
                  ("Customer", bot_phrase[1] if c.lang == "sv" else bot_phrase[0]),
                  ("Bot", c.t("Thanks. I'll connect you to an agent who can help.",
                              "Tack. Jag kopplar dig till en handläggare som kan hjälpa dig."))]
    if c.channel == "chat":
        turns.append(("Agent", c.t("Hi! You're chatting with [AGENT_NAME]. How can I help?",
                                   "Hej! Du chattar med [AGENT_NAME]. Vad kan jag hjälpa till med?")))
    else:
        turns.append(("Agent", c.t(["Welcome to customer service, you're speaking with [AGENT_NAME]. How can I help you?",
                                    "Hi, my name is [AGENT_NAME], what can I help you with today?"],
                                   ["Välkommen till kundservice, du pratar med [AGENT_NAME]. Vad kan jag hjälpa dig med?",
                                    "Hej, jag heter [AGENT_NAME], vad kan jag hjälpa dig med i dag?"])))
    return turns


def verification(c: Ctx) -> list[tuple[str, str]]:
    if c.channel == "chat":
        return [("Agent", c.t("To look at your account, please log in with BankID via the link I just sent.",
                              "För att kunna titta på ditt konto behöver du logga in med BankID via länken jag skickade.")),
                ("Customer", c.t("Done.", "Klart."))]
    return [("Agent", c.t("Before we start, can I have your personal identity number?",
                          "Innan vi börjar, kan jag få ditt personnummer?")),
            ("Customer", c.t("Yes, it's [PERSONNUMMER].", "Ja, det är [PERSONNUMMER].")),
            ("Agent", c.t("Thank you, [CUSTOMER_NAME]. I can see your account now.",
                          "Tack, [CUSTOMER_NAME]. Nu ser jag ditt konto."))]


def closing(c: Ctx) -> list[tuple[str, str]]:
    bye_voice = c.t("Thank you for calling, have a nice day!", "Tack för att du ringde, ha en fin dag!")
    bye_chat = c.t("Thanks for chatting with us, have a nice day!", "Tack för att du chattade med oss, ha en fin dag!")
    bye = bye_chat if c.channel == "chat" else bye_voice
    if c.resolved:
        return [("Agent", c.t("Is there anything else I can help you with?", "Finns det något mer jag kan hjälpa dig med?")),
                ("Customer", c.t(["No, that was all. Thanks for the help.", "No, that's it. Thank you!"],
                                 ["Nej, det var allt. Tack för hjälpen.", "Nej, det var bra så. Tack!"])),
                ("Agent", bye)]
    return [("Agent", c.t("Is there anything else I can help you with today?", "Finns det något mer jag kan hjälpa dig med i dag?")),
            ("Customer", c.t(["No. I just hope this gets sorted out soon.", "No. But I'm not happy with how this has been handled."],
                             ["Nej. Jag hoppas bara att det här löser sig snart.", "Nej. Men jag är inte nöjd med hur det här har hanterats."])),
            ("Agent", c.t("I understand, and I'm sorry for the inconvenience.", "Jag förstår, och jag ber om ursäkt för besväret."))]


def render_transcript(turns: list[tuple[str, str]], duration_sec: int) -> str:
    total_chars = sum(len(t) for _, t in turns) or 1
    elapsed, lines = 0.0, []
    for speaker, text in turns:
        lines.append(f"[{int(elapsed) // 60:02d}:{int(elapsed) % 60:02d}] {speaker}: {text}")
        elapsed += duration_sec * len(text) / total_chars
    return "\n".join(lines)


def queue_for(scn: Scenario, business_type: str, channel: str, handled_by: str) -> tuple[str, str]:
    if handled_by == "virtual_agent":
        return f"{business_type}_Voicebot", scn.lob
    lob_code = {"Mobile": "Mobile", "Fixed Broadband": "Fixed", "TV": "TV"}[scn.lob]
    suffix = "_Chat" if channel == "chat" else ""
    return f"{business_type}_{lob_code}_{scn.area}{suffix}", scn.lob


def generate(args) -> None:
    rng = random.Random(args.seed)
    tl = Timeline(end=args.end)
    customers = build_customers(rng, args.customers, tl)
    picker = CustomerPicker(rng, customers, tl)

    # 1. plan primary contacts per day/scenario
    planned: list[dict] = []
    d = tl.start
    while d <= tl.end:
        weekday_factor = 0.55 if d.weekday() >= 5 else 1.0
        for scn in SCENARIOS:
            lam = scn.daily_rate * scn.profile(d, tl) * weekday_factor * args.scale
            for _ in range(poisson(rng, lam)):
                planned.append({"scn": scn, "date": d, "followup": False, "prev": None, "customer": picker.pick(scn.customer_pool, d)})
        d += timedelta(days=1)

    # 2. realise contacts, scheduling follow-ups (repeat contacts) for unresolved ones
    queue = sorted(planned, key=lambda p: p["date"])
    contacts: list[dict] = []
    i = 0
    while i < len(queue):
        p = queue[i]
        i += 1
        contact = realise_contact(rng, tl, p)
        contacts.append(contact)
        scn = p["scn"]
        n_prev = p.get("n", 0)
        if not contact["gt"]["resolved"] and n_prev < 2 and rng.random() < scn.repeat_prob_unresolved:
            nd = p["date"] + timedelta(days=rng.randint(1, 6))
            if nd <= tl.end:
                fu = {"scn": scn, "date": nd, "followup": True, "prev": p["date"], "customer": p["customer"], "n": n_prev + 1,
                      "prev_channel": contact["metrics"]["channel"]}
                # keep queue roughly ordered by date
                j = i
                while j < len(queue) and queue[j]["date"] <= nd:
                    j += 1
                queue.insert(j, fu)

    # 3. churn flags (customer-level churn date, derived per contact)
    for c in contacts:
        cust: Customer = c["customer"]
        m = c["metrics"]
        d0 = c["date"]
        m["churned_within_30d"] = bool(cust.churn_date and 0 <= (cust.churn_date - d0).days <= 30)

    # 4. queue congestion -> ASA
    per_day: dict[date, int] = {}
    for c in contacts:
        per_day[c["date"]] = per_day.get(c["date"], 0) + 1
    median_day = sorted(per_day.values())[len(per_day) // 2]
    for c in contacts:
        m = c["metrics"]
        if m["handled_by"] == "virtual_agent":
            m["asa_sec"] = 0
        else:
            congestion = per_day[c["date"]] / median_day
            base = 25 if m["channel"] == "chat" else 70
            m["asa_sec"] = int(base * congestion ** 2 * rng.lognormvariate(0, 0.5))
        if m["csat_score"] is not None and m["asa_sec"] > 240:
            m["csat_score"] = max(1, m["csat_score"] - 1)

    write_outputs(args, rng, tl, contacts)


def realise_contact(rng: random.Random, tl: Timeline, p: dict) -> dict:
    scn: Scenario = p["scn"]
    d: date = p["date"]
    cust: Customer = p["customer"]
    followup = p["followup"]

    lang = "sv" if ("sv" in scn.languages and rng.random() < 0.35) else "en"
    bot_only = scn.bot_dialogue is not None and rng.random() < scn.bot_only_prob
    if bot_only:
        channel = "voice"
    elif followup and p.get("prev_channel") == "chat":
        channel = "voice" if rng.random() < 0.7 else "chat"
    else:
        channel = "chat" if rng.random() < scn.chat_share else "voice"
    handled_by = "virtual_agent" if bot_only else "agent"
    voicebot_first = (not bot_only) and channel == "voice" and rng.random() < 0.35

    resolved = rng.random() < (scn.resolved_prob * (0.8 if followup else 1.0))
    if scn.key == "router_firmware_wifi" and d < tl.firmware_known:
        resolved = rng.random() < 0.15
    churn_intent = rng.random() < scn.churn_intent_prob
    self_service = rng.random() < scn.self_service_prob

    competitor = None
    if churn_intent or scn.key == "number_porting":
        competitor = rng.choice(FIXED_COMPETITORS if (scn.lob == "Fixed Broadband" or (scn.key == "churn_competitor" and cust.has_fixed and not cust.has_mobile)) else MOBILE_COMPETITORS)

    c = Ctx(rng=rng, lang=lang, channel=channel, contact_date=d, customer=cust, tl=tl, followup=followup,
            prev_date=p["prev"], resolved=resolved, self_service=self_service, churn_intent=churn_intent)
    if competitor:
        c.v.update(competitor=competitor[0], competitor_offer=competitor[1], competitor_offer_sv=competitor[2])

    if bot_only:
        body = scn.bot_dialogue(c)
        turns = body
    else:
        body = scn.dialogue(c)
        turns = opening(c, voicebot_first, scn.bot_phrase)
        turns.append(body[0])
        turns += verification(c)
        turns += body[1:]
        secondary_key = None
        if rng.random() < 0.15:
            options = [k for k in SECONDARY_SNIPPETS if k != scn.key and (k != "price_plan_migration" or d >= tl.migration_email)]
            secondary_key = rng.choice(options)
            en_c, en_a, sv_c, sv_a = SECONDARY_SNIPPETS[secondary_key]
            use_sv = lang == "sv" and sv_c is not None
            turns += [("Customer", sv_c if use_sv else en_c), ("Agent", sv_a if use_sv else en_a)]
        c.facts["secondary_key"] = secondary_key
        transferred = rng.random() < scn.transfer_prob
        c.facts["transferred"] = transferred
        if transferred:
            turns += [("Agent", c.t("I'm going to transfer you to our second-line specialists who can look into this further. Please hold.",
                                    "Jag kopplar dig vidare till våra specialister i andra linjen som kan titta närmare på det här. Ett ögonblick.")),
                      ("Agent", c.t("Hi, this is [AGENT_NAME] from second line. I've read the notes from my colleague.",
                                    "Hej, det här är [AGENT_NAME] från andra linjen. Jag har läst min kollegas anteckningar."))]
        turns += closing(c)

    # churn outcome at customer level
    churn_p = scn.churn_prob * (1.5 if not resolved else 0.6) * (1.4 if followup else 1.0)
    if scn.key == "churn_competitor":
        churn_p = 0.9 if not resolved else 0.05
    if cust.business_type == "B2C" and cust.churn_date is None and rng.random() < churn_p:
        cust.churn_date = d + timedelta(days=rng.randint(3, 25))

    # operational metrics
    talk = int(scn.talk_mean_sec * rng.lognormvariate(0, 0.35) * (1.2 if followup else 1.0))
    if bot_only:
        talk, hold, mute, acw = rng.randint(60, 160), 0, 0, 0
    else:
        hold = int(talk * rng.uniform(0.0, 0.12) + (rng.randint(60, 240) if c.facts.get("transferred") else 0))
        mute = int(talk * rng.uniform(0.02, 0.15 if scn.lob == "Fixed Broadband" else 0.08))
        acw = rng.randint(30, 150)
    if channel == "chat":
        talk = int(talk * 1.6)
    start_local = random_local_ts(rng, d)
    aht = talk + hold + acw
    end_local = start_local + timedelta(seconds=talk + hold)
    survey_rate = 0.4 if channel == "chat" else 0.3
    csat = None
    if rng.random() < survey_rate:
        mu = scn.csat_mean + (0.5 if resolved else -0.7) - (0.4 if followup else 0) - (0.3 if c.facts.get("transferred") else 0)
        if scn.key == "final_invoice" and bot_only:
            mu -= 1.5
        csat = int(min(5, max(1, round(rng.gauss(mu, 0.8)))))

    conv_id = stable_id("CONV-", scn.key, d, cust.key, rng.random())
    queue_name, lob = queue_for(scn, cust.business_type, channel, handled_by)
    if handled_by == "agent" and rng.random() < 0.008:
        queue_name = "B2C_Reklamation"

    metrics = {
        "conversation_id": conv_id,
        "customer_key": cust.key,
        "started_at": ts(start_local),
        "ended_at": ts(end_local),
        "channel": channel,
        "contact_type": "chat" if channel == "chat" else ("callback" if rng.random() < 0.08 else "inbound"),
        "queue_name": queue_name,
        "business_type": cust.business_type,
        "line_of_business": lob,
        "region": cust.region,
        "tenure_months": cust.tenure_months(d),
        "language": lang,
        "handled_by": handled_by,
        "voicebot_attempted": bot_only or voicebot_first,
        "asa_sec": 0,
        "talk_sec": talk,
        "hold_sec": hold,
        "mute_sec": mute,
        "acw_sec": acw,
        "aht_sec": aht,
        "transferred": bool(c.facts.get("transferred")),
        "csat_score": csat,
        "churned_within_30d": False,
        "source_system": "genesys",
        "ingested_at": ts(datetime.combine(d + timedelta(days=1), time(3, rng.randint(0, 59)), timezone.utc)),
    }
    transcript = {
        "conversation_id": conv_id,
        "channel": channel,
        "language": lang,
        "started_at": metrics["started_at"],
        "transcript_text": render_transcript(turns, talk + hold),
        "turn_count": len(turns),
        "source_system": "genesys",
        "ingested_at": metrics["ingested_at"],
    }
    secondary_key = c.facts.get("secondary_key")
    gt = {
        "conversation_id": conv_id,
        "gt_scenario": scn.key,
        "gt_topic": scn.topic,
        "gt_theme": scn.theme,
        "gt_secondary_topic": SCN[secondary_key].topic if secondary_key else None,
        "gt_is_followup": followup,
        "resolved": resolved,
        "self_service": self_service,
        "churn_intent": churn_intent,
        "competitor": competitor[0] if competitor else None,
        "hardware_model": c.facts.get("hardware_model"),
        "network_operator": c.facts.get("network_operator"),
    }
    return {"date": d, "customer": cust, "scn": scn, "metrics": metrics, "transcript": transcript, "gt": gt,
            "facts": dict(c.facts), "competitor": competitor, "turns": turns, "lang": lang}


def fallback_insight(rng: random.Random, c: dict) -> dict:
    scn: Scenario = c["scn"]
    gt, facts, comp = c["gt"], c["facts"], c["competitor"]
    resolved = gt["resolved"]
    score = scn.sentiment_base + (0.3 if resolved else -0.3) - (0.2 if gt["gt_is_followup"] else 0)
    score = round(max(-1.0, min(1.0, score + rng.uniform(-0.15, 0.15))), 2)
    first_customer = next((t for s, t in c["turns"] if s == "Customer"), "")
    resolution = facts.get("resolution") or scn.resolution
    termination = scn.key == "churn_competitor"
    return {
        "conversation_id": gt["conversation_id"],
        "summary": f"Customer contacted us about: {scn.topic.lower()}. {resolution}." + ("" if resolved else " Not resolved in contact."),
        "primary_issue": scn.topic.lower(),
        "secondary_issues": [gt["gt_secondary_topic"].lower()] if gt["gt_secondary_topic"] else [],
        "journey_step": scn.journey_step,
        "product_area": scn.lob,
        "hardware_model": facts.get("hardware_model"),
        "network_operator": facts.get("network_operator"),
        "customer_sentiment": "negative" if score < -0.25 else ("positive" if score > 0.25 else "neutral"),
        "sentiment_score": score,
        "trigger_event": facts.get("trigger_event", scn.trigger) or None,
        "root_cause": facts.get("root_cause", scn.root_cause) or None,
        "resolution": resolution,
        "resolved_in_contact": resolved,
        "failure_demand": scn.failure_demand,
        "self_service_attempted": gt["self_service"],
        "repeat_contact_mentioned": gt["gt_is_followup"],
        "churn_risk": "high" if (termination and not resolved) else ("medium" if gt["churn_intent"] or score < -0.5 else "low"),
        "termination_requested": termination,
        "competitor_name": comp[0] if comp else None,
        "competitor_offer": comp[1] if comp else None,
        "competitor_price_sek": float(comp[3]) if comp else 0.0,
        "evidence_quote": first_customer,
        "confidence": round(rng.uniform(0.62, 0.8) if gt["gt_secondary_topic"] else rng.uniform(0.78, 0.98), 2),
        "model_version": "fallback-ground-truth",
        "prompt_version": "n/a",
        "enriched_at": c["metrics"]["ingested_at"],
    }


def write_jsonl(path: Path, rows) -> int:
    n = 0
    with path.open("w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
            n += 1
    return n


def write_outputs(args, rng: random.Random, tl: Timeline, contacts: list[dict]) -> None:
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    contacts.sort(key=lambda c: c["metrics"]["started_at"])

    metrics_rows = []
    for c in contacts:
        m = c["metrics"]
        if rng.random() < 0.02:  # late-arriving: lands 2-3 days after the contact
            late = datetime.strptime(m["started_at"], "%Y-%m-%d %H:%M:%S+00:00").replace(tzinfo=timezone.utc) + timedelta(days=rng.randint(2, 3))
            m["ingested_at"] = ts(late)
        metrics_rows.append(m)
        if rng.random() < 0.007:  # duplicate delivery of the same conversation
            dup = dict(m)
            dup["ingested_at"] = ts(datetime.strptime(m["ingested_at"], "%Y-%m-%d %H:%M:%S+00:00").replace(tzinfo=timezone.utc) + timedelta(hours=6))
            metrics_rows.append(dup)

    transcripts = [c["transcript"] for c in contacts if c["metrics"]["channel"] == "chat" or rng.random() < 0.97]
    with_transcript = {t["conversation_id"] for t in transcripts}

    n_tr = write_jsonl(out / "transcripts.jsonl", transcripts)
    n_m = write_jsonl(out / "interaction_metrics.jsonl", metrics_rows)
    with (out / "interaction_metrics.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(metrics_rows[0].keys()))
        w.writeheader()
        w.writerows(metrics_rows)

    write_jsonl(out / "ground_truth.jsonl", (c["gt"] for c in contacts))
    eligible = [c for c in contacts if c["metrics"]["conversation_id"] in with_transcript and c["metrics"]["queue_name"] != "B2C_Reklamation"]
    write_jsonl(out / "fallback_conversation_insights.jsonl", (fallback_insight(rng, c) for c in eligible))
    write_jsonl(out / "fallback_topic_catalog.jsonl",
                ({"topic_name": s.topic.lower(), "theme": s.theme, "description": s.description} for s in SCENARIOS))
    write_jsonl(out / "fallback_topic_recommendations.jsonl",
                ({"topic_name": s.topic.lower(), "problem_statement": s.problem_statement, "recommended_action": s.recommended_action,
                  "suggested_owner": s.owner, "expected_impact": s.expected_impact} for s in SCENARIOS))

    by_scn: dict[str, int] = {}
    for c in contacts:
        by_scn[c["scn"].key] = by_scn.get(c["scn"].key, 0) + 1
    print(f"Period: {tl.start} .. {tl.end}")
    print(f"Contacts: {len(contacts)} | metric rows (incl. duplicates): {n_m} | transcripts: {n_tr}")
    print("Storyline dates: migration email", tl.migration_email, "| firmware push", tl.firmware_push,
          "| BankID incident", tl.bankid_incident[0], "..", tl.bankid_incident[1])
    for k, v in sorted(by_scn.items(), key=lambda kv: -kv[1]):
        print(f"  {k:<24} {v:>5}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=str(Path(__file__).resolve().parent.parent / "data"))
    ap.add_argument("--end", type=date.fromisoformat, default=date.today(), help="last day of data (YYYY-MM-DD), default today")
    ap.add_argument("--scale", type=float, default=1.0, help="volume multiplier (1.0 ≈ 6-7k conversations)")
    ap.add_argument("--customers", type=int, default=8000)
    ap.add_argument("--seed", type=int, default=42)
    generate(ap.parse_args())


if __name__ == "__main__":
    main()
