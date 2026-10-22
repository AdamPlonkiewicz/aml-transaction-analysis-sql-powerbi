-- =====================================================
-- 07_dashboard_sample_accounts.sql
-- Wybór przykładowych kont do wykresów osi czasu.
-- Dla każdego z trzech schematów: jedno typowe konto prania
-- i jedno konto legalne z odpowiadającej typologii normalnej.
--
-- Kryteria:
-- - konto prania: mediana liczby transakcji w typologii, >= 2 aktywne
--   miesiące, najdłuższy okres aktywności,
-- - konto legalne: ta sama liczba transakcji co konto prania (jeśli to
--   możliwe) albo mediana typologii normalnej; bez żadnej transakcji
--   prania (ani jako nadawca, ani jako odbiorca).
--
-- Cel: pokazać różnicę w rozłożeniu transakcji w czasie (serie vs
-- równomierna aktywność).
-- =====================================================

WITH accounts AS(
	SELECT
		sender_id,
		COUNT(*) AS tx_count,
		COUNT(DISTINCT DATE_TRUNC('month', transaction_datetime )) AS active_months,
		MIN(transaction_datetime) AS min_date,
		MAX(transaction_datetime) AS max_date
	FROM aml_transactions_clean 
	WHERE laundering_type = 'Cash_Withdrawal'
	GROUP BY sender_id 
)
SELECT
	sender_id,
	tx_count,
	min_date,
	max_date,
	active_months
FROM accounts 
WHERE tx_count = (SELECT PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY tx_count) FROM accounts)
AND active_months >= 2
ORDER BY active_months DESC, max_date - min_date DESC 
LIMIT 1;
-- Konto prania (Cash_Withdrawal): mediana liczby wypłat na konto = 15.
-- Kryterium: tx_count = mediana, >= 2 aktywne miesiące, najdłuższy
-- okres aktywności. Wynik: 7350260408_UK (15 wypłat, 3 miesiące,
-- 01-08.2023).


SELECT
	sender_id,
	COUNT(*) AS tx_count,
	MIN(transaction_datetime) AS min_date,
	MAX(transaction_datetime) AS max_date,
	MAX(transaction_datetime) - MIN(transaction_datetime) AS activity_duration
FROM aml_transactions_clean 
WHERE laundering_type = 'Normal_Cash_Withdrawal' AND payment_type = 'Cash Withdrawal' AND sender_id NOT IN (
    SELECT sender_id   FROM aml_transactions_clean WHERE is_laundering = 1
    UNION
    SELECT receiver_id FROM aml_transactions_clean WHERE is_laundering = 1
)
GROUP BY sender_id 
HAVING COUNT(*) = 15
ORDER BY activity_duration DESC
LIMIT 1;
-- Konto legalne (Normal_Cash_Withdrawal, tylko wypłaty gotówki):
-- tyle samo wypłat co konto prania (15), najdłuższy okres aktywności.
-- Wynik: 7961549830_UK (15 wypłat, 10.2022 - 08.2023, 318 dni).
-- Para Cash_Withdrawal: 7350260408_UK (pranie) vs 7961549830_UK (legalne).



WITH accounts AS(
	SELECT
		receiver_id,
		COUNT(*) AS tx_count,
		COUNT(DISTINCT DATE_TRUNC('month', transaction_datetime )) AS active_months,
		MIN(transaction_datetime) AS min_date,
		MAX(transaction_datetime) AS max_date
	FROM aml_transactions_clean 
	WHERE laundering_type = 'Smurfing'
	GROUP BY receiver_id 
)
SELECT
	receiver_id,
	tx_count,
	min_date,
	max_date,
	active_months
FROM accounts 
WHERE tx_count = (SELECT PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY tx_count) FROM accounts)
AND active_months >= 2
ORDER BY active_months DESC, max_date - min_date DESC 
LIMIT 1;
-- Konto prania (Structuring, etykieta SAML-D: Smurfing): mediana liczby
-- wpłat na odbiorcę = 15.
-- Wynik: 8156879059_UK (15 wpłat gotówkowych, 3 miesiące, 10.2022 - 08.2023).


SELECT
	receiver_id,
	COUNT(*) AS tx_count,
	MIN(transaction_datetime) AS min_date,
	MAX(transaction_datetime) AS max_date,
	MAX(transaction_datetime) - MIN(transaction_datetime) AS activity_duration
FROM aml_transactions_clean 
WHERE laundering_type = 'Normal_Cash_Deposits' AND receiver_id NOT IN (
    SELECT sender_id   FROM aml_transactions_clean WHERE is_laundering = 1
    UNION
    SELECT receiver_id FROM aml_transactions_clean WHERE is_laundering = 1
)
GROUP BY receiver_id 
HAVING COUNT(*) = 15
ORDER BY activity_duration DESC
LIMIT 1;
-- Konto legalne (Normal_Cash_Deposits): 15 wpłat, najdłuższy okres
-- aktywności. Wynik: 7133153926_UK (10.2022 - 08.2023, 317 dni).
-- Para Structuring (etykieta SAML-D: Smurfing)): 8156879059_UK (pranie) vs 7133153926_UK (legalne).


WITH accounts AS(
	SELECT
		receiver_id,
		COUNT(*) AS tx_count,
		COUNT(DISTINCT DATE_TRUNC('month', transaction_datetime )) AS active_months,
		MIN(transaction_datetime) AS min_date,
		MAX(transaction_datetime) AS max_date
	FROM aml_transactions_clean 
	WHERE laundering_type = 'Structuring'
	GROUP BY receiver_id 
)
SELECT
	receiver_id,
	tx_count,
	min_date,
	max_date,
	active_months
FROM accounts 
WHERE tx_count = (SELECT PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY tx_count) FROM accounts)
AND active_months >= 2
ORDER BY active_months DESC, max_date - min_date DESC 
LIMIT 1;

-- Konto prania (Smurfing, etykieta SAML-D: Structuring): mediana liczby
-- wpłat na odbiorcę = 24. Kryterium jak w poprzednich parach.
-- Wynik: 434351836_UK (24 wpłaty, 3 miesiące, 10.2022 - 08.2023).

SELECT
	receiver_id,
	COUNT(*) AS tx_count,
	MIN(transaction_datetime) AS min_date,
	MAX(transaction_datetime) AS max_date,
	MAX(transaction_datetime) - MIN(transaction_datetime) AS activity_duration
FROM aml_transactions_clean 
WHERE laundering_type = 'Normal_Fan_In'
GROUP BY receiver_id 
HAVING COUNT(*) = 24
ORDER BY activity_duration DESC
LIMIT 1;
-- Normal_Fan_In z dokładnie 24 wpływami: najdłuższy okres aktywności
-- to 9,5 godziny - konta z tak małą liczbą
-- wpływów to wyłącznie konta ucięte na końcu zbioru. Typowy legalny
-- odbiorca fan-in ma setki wpływów; kryterium "ta sama liczba transakcji"
-- nie ma tu zastosowania. Konto legalne należy wybrać jako mediane
-- liczby wpływów wśród odbiorców Normal_Fan_In.

WITH accounts AS(
	SELECT
		receiver_id,
		COUNT(*) AS tx_count,
		COUNT(DISTINCT DATE_TRUNC('month', transaction_datetime )) AS active_months,
		MIN(transaction_datetime) AS min_date,
		MAX(transaction_datetime) AS max_date
	FROM aml_transactions_clean 
	WHERE laundering_type = 'Normal_Fan_In' AND receiver_id NOT IN (
    SELECT sender_id   FROM aml_transactions_clean WHERE is_laundering = 1
    UNION
    SELECT receiver_id FROM aml_transactions_clean WHERE is_laundering = 1
)
	GROUP BY receiver_id 
)
SELECT
	receiver_id,
	tx_count,
	min_date,
	max_date,
	active_months
FROM accounts 
WHERE tx_count = (SELECT PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY tx_count) FROM accounts)
ORDER BY active_months DESC, max_date - min_date DESC 
LIMIT 1;
-- Konto legalne (Normal_Fan_In, mediana liczby wpływów = 168):
-- 3442175873_UK - 168 wpływów w ciągu jednego dnia (09.01.2023).
-- Legalne konta fan-in to jednodniowe zrywy od kilkunastu stałych
-- nadawców; pranie (434351836_UK) to kilka serii od jednorazowych
-- nadawców. Dla tej pary różnicuje struktura nadawców, nie czas.

WITH stats AS ( 
	SELECT 
		receiver_id,
		COUNT(DISTINCT transaction_datetime::date) AS active_days
	FROM aml_transactions_clean
	WHERE laundering_type  = 'Normal_Fan_In'
	GROUP BY receiver_id
)
SELECT 
	active_days,
	COUNT(*) AS receiver_count
FROM stats
GROUP BY active_days
ORDER BY active_days;
-- Transakcje Normal_Fan_In każdego odbiorcy (12 985) występują w jednym
-- dniu - legalny fan-in w SAML-D to jednodniowy zryw od kilkunastu
-- powtarzających się nadawców (cecha generatora). 

SELECT 
	*
FROM aml_transactions_clean
WHERE receiver_id = '3442175873_UK';

-- Podgląd konta legalnego 3442175873_UK: 168 wpływów Normal_Fan_In
-- w jednym dniu (09.01.2023) od ok. 14 nadawców wpłacających wielokrotnie;
-- poza tym 27 zwykłych transakcji rozłożonych na cały rok.
-- Kwota stała w obrębie nadawcy, ale różna między nadawcami
-- (4,9k-18,7k) - reguła Smurfing (kwoty nowych nadawców w granicach 10%)
-- słusznie nie flaguje tego konta.

-- =====================================================
-- PODSUMOWANIE – pary kont do raportu
-- =====================================================
-- Schemat (etykieta SAML-D)          | Konto prania   | Konto legalne
-- -----------------------------------+----------------+---------------
-- Cash withdrawal (Cash_Withdrawal)  | 7350260408_UK  | 7961549830_UK
-- Structuring (Smurfing)             | 8156879059_UK  | 7133153926_UK
-- Smurfing (Structuring)             | 434351836_UK   | 3442175873_UK
-- =====================================================
