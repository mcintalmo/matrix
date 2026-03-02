# Matrix Authentication Service (MAS) Setup

This guide walks you through enabling modern OIDC-based authentication with phone number support.

## What is MAS?

Matrix Authentication Service (MAS) replaces Synapse's built-in password authentication with a modern OIDC provider that supports:

- **Phone number authentication** (SMS/WhatsApp verification)
- **Email authentication**
- **Social login** (Google, GitHub, Apple, etc.)
- **Passkeys / WebAuthn** (future)
- **Centralized session management**
- **Account recovery flows**

## Architecture

```
User → Nginx → MAS (port 8090) → Synapse (port 8008)
              ↓
         Postgres (mas database)
```

**Traffic Routing:**
- `/_auth/*` → MAS (login UI, account management)
- `/_matrix/client/.../login` → MAS (delegated auth)
- `/_matrix/*` → Synapse (all other Matrix traffic)

## Prerequisites

✅ Working Synapse installation
✅ PostgreSQL database
✅ SSL certificates for your domain
✅ `.env` file with MAS secrets (generated via `make init-env`)

## Deployment Steps

### 1. Generate Environment Secrets

If you haven't already generated MAS secrets in your `.env`:

```bash
# On your local machine
make init-env
```

This generates:
- `MAS_DB_PASSWORD` - Database password
- `MAS_ENCRYPTION_SECRET` - Encrypts sensitive data
- `MAS_SIGNING_KEY` - Signs OIDC tokens
- `MAS_SYNAPSE_SHARED_SECRET` - Shared with Synapse
- `MAS_ADMIN_TOKEN` - Admin API access

### 2. Deploy Configuration

```bash
# Deploy all updated files to server
make deploy
```

This deploys:
- `mas/config.yaml` - MAS configuration
- `docker-compose.yml` - Includes MAS service
- `config/custom.yaml` - Synapse MSC3861 delegation
- `nginx.conf` - Auth traffic routing

### 3. Create MAS Database

```bash
# Create database and user in Postgres
make setup-mas-db
```

### 4. Start MAS Service

```bash
# Start all services (or just mas)
make docker-up  # or: make ssh-cmd CMD="docker compose up -d mas"
```

### 5. Initialize MAS Database

```bash
# Run database migrations
make mas-init
```

### 6. Restart Synapse with MSC3861

```bash
# Apply new Synapse config and restart
make docker-restart SERVICE=synapse
```

### 7. Create Admin User

```bash
# Interactive admin user creation
make mas-create-admin
```

Follow the prompts to create your first admin user.

### 8. Access MAS Admin UI

Visit: **https://matrix.rumpusroom.xyz/_auth/**

Log in with the admin credentials you just created.

## Configuration

### Enabling Phone Authentication

1. Access the MAS admin UI: https://matrix.rumpusroom.xyz/_auth/
2. Navigate to **Settings** → **Authentication Methods**
3. Enable **Phone Number** authentication
4. Configure SMS provider (Twilio, Vonage, AWS SNS, etc.)
5. Set your phone number format and validation rules

### Configuring SMS Provider (Twilio Example)

Edit `mas/config.yaml` and add:

```yaml
upstream_oauth2:
  providers:
    - id: twilio-sms
      issuer: https://api.twilio.com
      client_id: "YOUR_TWILIO_ACCOUNT_SID"
      client_secret: "YOUR_TWILIO_AUTH_TOKEN"
      scope: "phone"
      claims_imports:
        subject:
          template: "{{ user.phone_number }}"
```

Then:
```bash
make apply-config
make docker-restart SERVICE=mas
```

## Testing

### Check MAS Health

```bash
make mas-status
```

### View MAS Logs

```bash
make mas-logs
```

### Test Login Flow

1. Open Element: https://element.rumpusroom.xyz
2. Click **Sign In**
3. You should be redirected to MAS login page at `/_auth/login`
4. Try logging in with phone number or email

### Verify OIDC Endpoints

```bash
# Check OIDC discovery
curl https://matrix.rumpusroom.xyz/.well-known/openid-configuration

# Check MAS health
curl https://matrix.rumpusroom.xyz/_auth/health
```

## Troubleshooting

### MAS won't start

**Check logs:**
```bash
make mas-logs
```

**Common issues:**
- Missing environment variables → Check `.env` file
- Database connection failed → Run `make setup-mas-db`
- Port conflict → Ensure nothing else uses port 8090

### Synapse won't start after MSC3861

**Check Synapse logs:**
```bash
make docker-logs SERVICE=synapse
```

**Common issues:**
- `client_secret` mismatch → Ensure `MAS_SYNAPSE_SHARED_SECRET` matches in both configs
- Invalid issuer URL → Must be `https://matrix.rumpusroom.xyz/` (with trailing slash)

### Login redirects to wrong URL

**Check nginx routing:**
```bash
make ssh-cmd CMD="docker compose exec nginx nginx -t"
```

Ensure location blocks are in correct order (MAS routes must come BEFORE `/_matrix`).

### Users can't register

**With MAS, registration works differently:**
1. Admin creates invite links in MAS UI
2. Users follow invitation link
3. They choose phone/email authentication
4. Account is created via MAS, synced to Synapse

## Migration from Old Authentication

If you have existing users with passwords:

1. **Users will need to recover their accounts:**
   - MAS can import existing Synapse user IDs
   - Users set new authentication method (phone/email)
   - Old passwords are disabled

2. **Admin migration steps:**
   ```bash
   # Coming soon: make mas-import-users
   ```

3. **Communication:**
   - Notify users of the change
   - Provide instructions for account recovery
   - Set grace period for transition

## Useful Commands

```bash
# Setup
make setup-mas-db          # Create MAS database
make mas-init              # Initialize schema
make mas-create-admin      # Create admin user

# Management
make mas-status            # Health check
make mas-logs              # View logs
make docker-restart SERVICE=mas  # Restart service

# Configuration
make edit-custom-config    # Edit Synapse MSC3861 config
make apply-config          # Deploy and restart
```

## Security Considerations

🔒 **Secrets Management:**
- MAS secrets are in `.env` (not in git)
- Shared secret must match between MAS and Synapse
- Admin token grants full API access - protect it

🔐 **Password Authentication:**
- Disabled when MSC3861 is enabled
- Old password hashes remain in database but are not used
- MAS handles all authentication

🌐 **HTTPS Required:**
- OIDC requires HTTPS in production
- Ensure SSL certificates are valid
- Use HSTS headers (already configured)

## References

- [MAS Documentation](https://element-hq.github.io/matrix-authentication-service/)
- [MSC3861: Matrix Authentication Service](https://github.com/matrix-org/matrix-spec-proposals/pull/3861)
- [Synapse Delegated Auth Docs](https://element-hq.github.io/synapse/latest/usage/configuration/config_documentation.html#experimental_features)
- [OIDC Specification](https://openid.net/specs/openid-connect-core-1_0.html)

## Next Steps

After MAS is working:

1. **Enable social login** (Google, GitHub, Apple)
2. **Configure email templates** (welcome, recovery, etc.)
3. **Setup phone number verification** (SMS provider)
4. **Customize branding** (logo, colors, terms)
5. **Monitor usage** (admin dashboard, metrics)

---

**Need help?** Check logs with `make mas-logs` or ask in #matrix:matrix.org
