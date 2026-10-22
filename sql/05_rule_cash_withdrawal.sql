-- =====================================================
-- 05_rule_cash_withdrawal.sql
-- Reguła: Cash withdrawal (wykrywa etykietę SAML-D: Cash_Withdrawal)

-- Definicja (literatura): wyprowadzanie środków z systemu bankowego
-- seriami częstych wypłat gotówki (etap integracji / wyjścia).
--
-- Profil w danych (03_typology_exploration.sql):
-- 1 konto -> 1 odbiorca, wyłącznie Cash Withdrawal, wypłaty ok. 15-350
-- GBP (sufit ok. 350), seria śr. 6,8 wypłat (maks. 10) w ok. 5 dni
-- (maks. 7), suma serii ok. 1,1 tys.
--
-- Etapy:
-- 1. Porównanie z normalnymi wypłatami gotówki
-- 2. Scenariusz reguły i progi
-- 3. Kontrola na całym zbiorze
-- 4. Walidacja z etykietą
-- =====================================================

-- 0. Test hipotezy z literatury: czy wypłaty poprzedza wpływ z prania?
WITH withdrawals AS (
	SELECT
		transaction_id,
		sender_id,
		transaction_datetime
	FROM aml_transactions_clean 
	WHERE laundering_type = 'Cash_Withdrawal'
)
SELECT 
	prev.laundering_type,
	COUNT(DISTINCT w.transaction_id) AS withdrawal_count
FROM withdrawals w 
LEFT JOIN aml_transactions_clean prev
	ON prev.receiver_id = w.sender_id 
	AND prev.transaction_datetime < w.transaction_datetime
	AND w.transaction_datetime - prev.transaction_datetime <= INTERVAL '30 days'
GROUP BY prev.laundering_type
ORDER BY withdrawal_count DESC;
-- Test powiązania wypłat z wcześniejszym praniem: wpływy na konto
-- wypłacającego w ciągu 30 dni przed wypłatą.
-- Wynik: 576 z 1334 wypłat (43%) bez żadnego wcześniejszego wpływu;
-- pozostałe poprzedzone wyłącznie wpływami normalnymi (Normal_*).
-- Wniosek: w SAML-D nie zamodelowano łańcucha "pranie -> wypłata
-- gotówki"; reguła opiera się wyłącznie na cechach samych wypłat.
-- W praktyce bankowej taki łańcuch można wykrywać, łącząc regułę
-- wypłat z flagami innych reguł (nie z etykietą danych).

-- 1. Porównanie z normalnymi wypłatami gotówki

SELECT
	laundering_type,
	COUNT(*) AS total_tx,
	COUNT(DISTINCT (sender_id, receiver_id)) AS pair_count,
	MIN(amount) AS min_amount,
	ROUND(AVG(amount),2) AS avg_amount,
	MAX(amount) AS max_amount
FROM aml_transactions_clean 
WHERE payment_type = 'Cash Withdrawal'
GROUP BY laundering_type
ORDER BY total_tx DESC;
-- Kwoty wypłat w praniu i w normalnych wypłatach są takie same
-- (10-350 GBP, średnio ok. 153) - kwota nie odróżnia typologii.
-- Normalne pary: śr. ok. 13 wypłat na parę w całym okresie danych;
-- Cash_Withdrawal: serie śr. ok. 7 wypłat w ok. 5 dni (eksploracja).
-- Hipoteza: typologie różni tempo wypłat - do sprawdzenia w regule.

-- 2. Scenariusz reguły i progi
WITH withdrawals AS (
	SELECT
		transaction_id,
		sender_id,
		receiver_id,
		laundering_type,
		transaction_datetime,
		COUNT(*) OVER (PARTITION BY sender_id, receiver_id ORDER BY transaction_datetime RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW) AS tx_count_7d
	FROM aml_transactions_clean 
	WHERE payment_type = 'Cash Withdrawal'
)
SELECT 
	laundering_type,
	COUNT(DISTINCT (sender_id, receiver_id)) FILTER (WHERE tx_count_7d >=4) AS pairs_min4,
	COUNT(DISTINCT (sender_id, receiver_id)) FILTER (WHERE tx_count_7d >=5) AS pairs_min5,
	COUNT(DISTINCT (sender_id, receiver_id)) FILTER (WHERE tx_count_7d >=6) AS pairs_min6
FROM withdrawals
GROUP BY laundering_type;
-- Test progów (liczba wypłat pary w kroczącym oknie 7 dni):
-- >= 4: 88/88 par prania, 5 720 fałszywych par (precyzja ok. 1,5%)
-- >= 5: 83/88, 867 fałszywych (ok. 8,7%)
-- >= 6: 78/88, 46 fałszywych (ok. 63%)
-- Normalne wypłaty również bywają częste - brak czystego rozdzielenia
-- samą liczbą wypłat.
-- Wstępna decyzja: próg >= 6 wypłat w 7 dni (89% wykrytych par).
-- Sprawdzane dodatkowe cechy: pora dnia, liczba wypłat dziennie.


SELECT 
	EXTRACT(HOUR FROM transaction_datetime) AS tx_hour,
	COUNT(*) FILTER (WHERE laundering_type = 'Cash_Withdrawal') AS laundering_tx_count,
	COUNT(*) FILTER (WHERE laundering_type = 'Normal_Cash_Withdrawal') AS normal_tx_count
FROM aml_transactions_clean 
WHERE payment_type = 'Cash Withdrawal'
GROUP BY EXTRACT(HOUR FROM transaction_datetime)
ORDER BY tx_hour;
-- Rozkład godzinowy wypłat: w obu grupach ten sam wzorzec
-- (mniej wypłat w godz. 0-7, więcej w 8-23); udział wypłat nocnych
-- ok. 23% w praniu i ok. 25% w normalnych wypłatach.
-- Wniosek: pora dnia nie odróżnia typologii.


WITH days AS (
	SELECT 
		laundering_type,
		sender_id,
		receiver_id,
		transaction_datetime::date AS tx_date,
		COUNT(*) AS tx_per_day
	FROM aml_transactions_clean
	WHERE payment_type = 'Cash Withdrawal'
	GROUP BY laundering_type,sender_id,receiver_id,transaction_datetime::date
)
SELECT 
	laundering_type,
	COUNT(*) AS tx_days,
	COUNT(*) FILTER (WHERE tx_per_day >=2) AS tx_days_2,
	ROUND(100.0 * COUNT(*) FILTER (WHERE tx_per_day >=2) / COUNT(*),2) AS pct_2,
	ROUND(AVG(tx_per_day),2) AS avg_tx_per_day,
	MAX(tx_per_day) AS max_tx_per_day
FROM days
GROUP BY laundering_type;
-- Wypłaty dziennie: w praniu 25% dni z wypłatami ma 2 wypłaty
-- (maks. 2), w normalnych wypłatach 5% dni ma >= 2 (maks. 4).
-- Cecha 5 razy częstsza w praniu, ale sama nie rozdziela grup
-- (ok. 14 tys. normalnych dni z >= 2 wypłatami).
-- Możliwe rozszerzenie reguły: niższy próg liczby wypłat w oknie
-- połączony z warunkiem "co najmniej 1 dzień z 2 wypłatami".
-- Decyzja: reguła pozostaje przy progu >= 6 wypłat w 7 dni.

WITH pairs AS (
	SELECT
		DISTINCT sender_id,
		receiver_id
	FROM aml_transactions_clean
	WHERE laundering_type ='Cash_Withdrawal'
)
SELECT 
	atc.laundering_type,
	COUNT(*) AS tx_count,
	COUNT( DISTINCT (atc.sender_id,atc.receiver_id)) AS pair_count
FROM pairs p
JOIN aml_transactions_clean atc
ON atc.sender_id = p.sender_id
AND atc.receiver_id = p.receiver_id 
WHERE atc.payment_type = 'Cash Withdrawal'
GROUP BY atc.laundering_type;
-- Pary wypłacające w schemacie Cash_Withdrawal (88) nie mają żadnych
-- normalnych wypłat gotówki - wszystkie ich wypłaty (1 334) należą
-- do serii prania. Para "pojawia się" od razu serią, bez wcześniejszej
-- historii wypłat.
-- Hipoteza do reguły: seria wypłat pary, która w poprzednich 30 dniach
-- nie wypłacała gotówki.



-- Test reguły behawioralnej: seria wypłat pary, która w 30 dniach
-- przed bieżącym tygodniem nie wypłacała gotówki.
WITH withdrawals AS (
    SELECT
        transaction_id,
        sender_id,
        receiver_id,
        laundering_type,
        transaction_datetime,
        COUNT(*) OVER w_7d    AS tx_count_7d,      -- wypłaty w ostatnich 7 dniach
        COUNT(*) OVER w_prior AS tx_count_prior    -- wypłaty w 30 dniach przed tym tygodniem
    FROM aml_transactions_clean
    WHERE payment_type = 'Cash Withdrawal'
    WINDOW
        w_7d AS (
            PARTITION BY sender_id, receiver_id
            ORDER BY transaction_datetime
            RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW
        ),
        w_prior AS (
            PARTITION BY sender_id, receiver_id
            ORDER BY transaction_datetime
            RANGE BETWEEN INTERVAL '37 days' PRECEDING AND INTERVAL '7 days' PRECEDING
        )
)
SELECT
    laundering_type,
    -- sama liczba wypłat (dotychczasowa reguła, dla porównania)
    COUNT(DISTINCT (sender_id, receiver_id)) FILTER (WHERE tx_count_7d >= 4) AS pairs_min4,
    COUNT(DISTINCT (sender_id, receiver_id)) FILTER (WHERE tx_count_7d >= 5) AS pairs_min5,
    COUNT(DISTINCT (sender_id, receiver_id)) FILTER (WHERE tx_count_7d >= 6) AS pairs_min6,
    -- liczba wypłat + brak wypłat w 30 dniach wcześniej
    COUNT(DISTINCT (sender_id, receiver_id)) FILTER (WHERE tx_count_7d >= 4 AND tx_count_prior = 0) AS pairs_min4_quiet,
    COUNT(DISTINCT (sender_id, receiver_id)) FILTER (WHERE tx_count_7d >= 5 AND tx_count_prior = 0) AS pairs_min5_quiet,
    COUNT(DISTINCT (sender_id, receiver_id)) FILTER (WHERE tx_count_7d >= 6 AND tx_count_prior = 0) AS pairs_min6_quiet
FROM withdrawals
GROUP BY laundering_type;
-- Wynik:
-- >= 6 w 7 dni:          78/88 par prania, 46 fałszywych (ok. 63%)
-- >= 6 w 7 dni + cisza:  77/88, 25 fałszywych (ok. 75%)
-- >= 5 + cisza:          82/88, 363 fałszywych (ok. 18%)
-- Warunek ciszy zmniejsza fałszywe alarmy o połowę prawie bez straty
-- wykryć.
-- Decyzja: >= 6 wypłat w 7 dni i 0 wypłat w 30 dniach wcześniej.


-- 3. Reguła finalna
DROP TABLE IF EXISTS flags_cash_withdrawal;

CREATE TABLE flags_cash_withdrawal AS
WITH withdrawals AS (
    SELECT
        transaction_id,
        sender_id,
        receiver_id,
        laundering_type,
        transaction_datetime,
        COUNT(*) OVER w_7d    AS tx_count_7d,      -- wypłaty w ostatnich 7 dniach
        COUNT(*) OVER w_prior AS tx_count_prior    -- wypłaty w 30 dniach przed tym tygodniem
    FROM aml_transactions_clean
    WHERE payment_type = 'Cash Withdrawal'
    WINDOW
        w_7d AS (
            PARTITION BY sender_id, receiver_id
            ORDER BY transaction_datetime
            RANGE BETWEEN INTERVAL '7 days' PRECEDING AND CURRENT ROW
        ),
        w_prior AS (
            PARTITION BY sender_id, receiver_id
            ORDER BY transaction_datetime
            RANGE BETWEEN INTERVAL '37 days' PRECEDING AND INTERVAL '7 days' PRECEDING
        )    
), triggers AS (
SELECT
	sender_id,
	receiver_id,
	transaction_datetime
FROM withdrawals
WHERE tx_count_7d >= 6 AND tx_count_prior = 0
)
SELECT
	DISTINCT w.transaction_id
FROM withdrawals w 
JOIN triggers t
ON w.sender_id = t.sender_id
AND w.receiver_id = t.receiver_id 
AND w.transaction_datetime BETWEEN t.transaction_datetime - INTERVAL '7 days' AND t.transaction_datetime; 

-- 4. Walidacja z etykietą
SELECT 
	atc.laundering_type,
	COUNT(*) AS total_tx,
	COUNT(f.transaction_id) AS flagged_tx
FROM aml_transactions_clean atc
LEFT JOIN flags_cash_withdrawal f ON atc.transaction_id = f.transaction_id
WHERE atc.payment_type  = 'Cash Withdrawal'
GROUP BY atc.laundering_type;
-- Walidacja (poziom transakcji, wypłaty gotówki):
-- Cash_Withdrawal: oflagowane 975 z 1 334 (wykrywalność 73,1%);
-- Normal_Cash_Withdrawal: 150 z 299 143 (0,05%).
-- Precyzja: 975 / 1 125 = 86,7%.
-- Wykrywalność transakcji niższa niż par (77/88): nie są łapane serie
-- krótsze niż 6 wypłat oraz serie następujące po przerwie < 30 dni
-- (warunek ciszy widzi poprzednią serię).
