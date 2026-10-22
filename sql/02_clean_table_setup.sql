-- =====================================================
-- 02_clean_table_setup.sql
-- Tabela robocza aml_transactions_clean na podstawie danych surowych.
--
-- Zmiany względem aml_transactions_raw:
-- - data i godzina połączone w jedną kolumnę transaction_datetime,
-- - identyfikator konta = numer konta + lokalizacja banku
--   (numer nie jest unikalny między bankami – wniosek z pliku 01),
-- - klucz główny transaction_id,
-- - indeksy pod analizę aktywności kont w czasie.
-- =====================================================

DROP TABLE IF EXISTS aml_transactions_clean;
CREATE TABLE aml_transactions_clean AS 
SELECT 
	(transaction_date ||' '|| transaction_time)::timestamp AS transaction_datetime,
	sender_account,
	(sender_account::VARCHAR(50) ||'_'|| sender_bank_location)::VARCHAR(50)   AS sender_id,
	receiver_account,
	(receiver_account::VARCHAR(50) ||'_'|| receiver_bank_location)::VARCHAR(50)   AS receiver_id,
	amount,
	payment_currency,
	received_currency,
	sender_bank_location,
	receiver_bank_location,
	payment_type,
	is_laundering,
	laundering_type
FROM aml_transactions_raw;

ALTER TABLE aml_transactions_clean
ADD COLUMN transaction_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY;

SELECT COUNT(*), MIN(transaction_datetime ), MAX(transaction_datetime )
FROM aml_transactions_clean;
-- Kontrola: 9 504 852 wierszy, zakres 2022-10-07 – 2023-08-23 (zgodnie z danymi surowymi).

CREATE INDEX idx_clean_sender_datetime ON aml_transactions_clean (sender_id, transaction_datetime);
CREATE INDEX idx_clean_receiver_datetime ON aml_transactions_clean (receiver_id, transaction_datetime);
ANALYZE aml_transactions_clean;