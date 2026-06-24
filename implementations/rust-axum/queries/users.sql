--! get_user
SELECT id, name, email, created_at FROM users WHERE id = :id;

--! list_users
SELECT id, name, email, created_at FROM users ORDER BY created_at DESC LIMIT 100;

--! insert_user
INSERT INTO users (name, email) VALUES (:name, :email) RETURNING id, name, email, created_at;

--! delete_user
DELETE FROM users WHERE id = :id RETURNING id;
