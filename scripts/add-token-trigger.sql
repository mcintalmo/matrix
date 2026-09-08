-- Automatically set default 365-day expiration on newly issued registration tokens
-- Only applies if expires_at is not explicitly provided (is NULL)
-- Can be modified or overridden at any time after insertion via standard UPDATE queries.

CREATE OR REPLACE FUNCTION set_default_registration_token_expiry()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.expires_at IS NULL THEN
        NEW.expires_at := COALESCE(NEW.created_at, NOW()) + INTERVAL '365 days';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_set_default_registration_token_expiry ON user_registration_tokens;

CREATE TRIGGER trg_set_default_registration_token_expiry
BEFORE INSERT ON user_registration_tokens
FOR EACH ROW
EXECUTE FUNCTION set_default_registration_token_expiry();
