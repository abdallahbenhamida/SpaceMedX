# Setup
- cp env.example .env

**SECRET_KEY:** openssl rand -hex 32 / python3 -c "import secrets; print(secrets.token_hex(32))"

# Using Makefile (make)

**Registered commands:**
- help
- up
- down
- build
- logs
- ps
- clean
- restart
- health
