INSERT INTO customer (customer_id, name, email, mobile_number, created_at, created_by) VALUES
(1, 'Client Demo A', 'a@example.invalid', '0600000001', CURRENT_DATE, 'fixture'),
(2, 'Client Demo B', 'b@example.invalid', '0600000002', CURRENT_DATE, 'fixture');
INSERT INTO accounts (customer_id, account_number, account_type, branch_address, created_at, created_by) VALUES
(1, 100001, 'Savings', 'Demo A', CURRENT_DATE, 'fixture'),
(2, 100002, 'Savings', 'Demo B', CURRENT_DATE, 'fixture');
