# Security

WonderShow Core is a local package and should not require secrets.

Please report security issues privately to the project maintainer before public disclosure. Do not include exploit details in a public issue until a fix is available.

Security expectations:

- local sidecars should bind to loopback by default;
- tokens, signing keys, payment credentials, and private user data must never be committed;
- example files should use dummy data only;
- plugins should document any network access they require.

