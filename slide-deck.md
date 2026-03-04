---
marp: true
theme: default
paginate: true
size: 16:9
html: true
style: |
  section {
    font-size: 28px;
  }
  section.lead h1 {
    font-size: 2.2em;
  }
  code {
    font-size: 0.85em;
  }
  pre {
    font-size: 0.75em;
  }
  .mermaid {
    font-size: 11px;
    transform: scale(0.68);
    transform-origin: center;
    margin: -40px 0;
  }
  table {
    font-size: 0.8em;
  }
  a {
    color: #1a5fb4;
  }
  .columns {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 1em;
  }
---

<script type="module">
  import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';
  mermaid.initialize({ startOnLoad: true });
</script>

# **Keycloak and EUDI-Wallet**

### A match made in heaven?

<!--
Welcome everyone. Today we'll dive deep into how we integrated the EU Digital Identity Wallet with Keycloak. We'll cover the full stack from credential issuance to verification, and share what we learned building this for a real government customer.
-->

---

# About Us

**Dominik Schlosser** — Freelance Software Architect
- Years of experience in the IAM space
- Migrated a large German authority's online IAM to Keycloak
- Created the Keycloak Cassandra extension, Infinispan removal & file-based storage

**Tom Schneider** — Software Developer at Bundesagentur für Arbeit
- Online IAM development
- Platform engineer for a Kubernetes-based private cloud

---

# Agenda

1. Introduction: EUDI-Wallet, Specs & Credential Types
2. **Credential Issuance** — OID4VCI with Keycloak
3. **Credential Presentation** — OID4VP Deep Dive
4. **Integrating OID4VP into Keycloak**
5. **Special Case: German PID Authentication**
6. Summary & Looking Ahead

<!--
We'll spend most of our time on OID4VP and the Keycloak integration since that's where the real complexity lives. I'll show real code from our implementation throughout.
-->

---

![bg 90% right](assets/eudi-wallet-smartphone-mockup.png)

# EU Digital Identity — Wallet

- Authenticate with online services
- Store and share credentials selectively
- Sign documents electronically
- Receive and share government attestations ("Nachweise")

**Our focus today: Authentication via Keycloak**

<!-- footer: https://ec.europa.eu/digital-building-blocks/sites/spaces/EUDIGITALIDENTITYWALLET/pages/791609471/What+is+the+Wallet -->

---

# EU Digital Identity — Origins & Specifications

- **eIDAS 2.0** (2024) — mandates digital identity wallets for every EU member state
- Independent sovereign solution, defined by the Architecture Reference Framework (ARF)

Two core protocols (built on OAuth 2.0):

| Spec | Purpose |
|------|---------|
| **OpenID4VCI** | **V**erifiable **C**redential **I**ssuance — getting credentials INTO the wallet |
| **OpenID4VP** | **V**erifiable **P**resentations — getting credentials OUT for verification |

<!-- footer: https://github.com/eu-digital-identity-wallet -->

<!--
eIDAS 2.0 mandates that every EU member state must offer a digital identity wallet to its citizens. The ARF defines how everything fits together. The two core protocols are OID4VCI for issuance and OID4VP for verification — both built on top of OAuth 2.0.
-->

---

<!-- footer: "" -->

# Credential Types

**`SD-JWT`** — Selective Disclosure for JWTs (RFC 9901)
- JSON-based, selective disclosure via salted hashes

**ISO `mDOC`** — Mobile Document
- CBOR-based, designed for proximity (NFC/BLE)

![bg fit right:57%](assets/sdjwt-example.png)

<!-- footer: "Try it yourself: https://sdjwt.co | Local debugging: https://github.com/dominikschlosser/oid4vc-dev" -->

<!--
We support both formats in our implementation, but SD-JWT is the primary format in the German ecosystem. mDOC is mainly used for the mobile driving license. You can explore SD-JWTs interactively at sdjwt.co. For local debugging of both SD-JWTs and mDOCs, check out oid4vc-dev on GitHub.
-->

---

<!-- footer: "" -->

# EUDI Ecosystem — Roles & Interactions

```
┌──────────────────────────────────────────────────────────────┐
│                      Trust Anchor (TSL)                      │
│          Publishes trusted entity lists (ETSI TS 119 612)    │
└───────┬──────────────────┬───────────────────┬───────────────┘
        │ trusts           │ trusts            │ trusts
        ▼                  ▼                   ▼
┌───────────────┐  ┌──────────────┐  ┌──────────────────────────┐
│  Credential   │  │    Wallet    │  │ Verifier / Relying Party │
│  Issuer       │  │   (Holder)   │  │ (e.g. Keycloak)          │
└───────┬───────┘  └──┬───────┬───┘  └──────────┬───────────────┘
        │  OID4VCI    │       │      OID4VP     │
        └─────────────┘       └─────────────────┘

┌───────────────────────┐  ┌──────────────────────────────────┐
│ Attestation Providers │  │ Status Provider                  │
│ (Registrars, Wallet   │  │ Token Status Lists (revocation)  │
│  Provider, Access CA) │  │                                  │
└───────────────────────┘  └──────────────────────────────────┘
```

<!--
This is the big picture. The Trust Anchor publishes trust lists so wallets can verify that issuers are legitimate, and verifiers can prove their identity. The Credential Issuer pushes credentials to the wallet via OID4VCI. The Verifier requests presentations from the wallet via OID4VP. Attestation Providers serve different roles — RP Registrars issue registration certificates for verifiers, the Wallet Provider issues wallet instance attestations, and Access CAs issue certificates to issuers and verifiers. The Status Provider hosts revocation lists. Keycloak sits on the verifier side in our setup.
-->

---

<!-- _class: lead -->

# Credential Issuance
## OID4VCI with Keycloak

---

# Keycloak OID4VCI — Preview Feature

- Built-in support since Keycloak 24+ (experimental)
- Implements the **Pre-Authorized Code Flow**
- Issuer metadata at `/.well-known/openid-credential-issuer`
- Credential signing using realm keys

<!--
Keycloak already has preview support for OID4VCI. It's not production-ready yet, but it gives us a foundation to build on. The pre-authorized code flow is simpler than the full authorization code flow because the user is already authenticated.
-->

---

# Pre-Authorized Code Flow

<div class="mermaid">
sequenceDiagram
    participant U as User
    participant KC as Keycloak
    participant W as Wallet
    U->>KC: Authenticate
    KC->>U: QR code (credential offer + pre-auth code)
    U->>W: Scan QR code
    W->>KC: Token request (pre-auth code)
    KC->>W: Access token + c_nonce
    W->>KC: Credential request + proof JWT
    KC->>W: Signed SD-JWT credential
</div>

<!--
The flow starts with the user authenticating normally. Keycloak then generates a credential offer containing a pre-authorized code. The wallet scans a QR code, exchanges the code for an access token AND a c_nonce. The nonce is used to build a proof-of-possession JWT, which the wallet sends along with the credential request. This proves the wallet controls the holder key that will be bound to the credential.
-->

---

# Credential Offer

```
openid-credential-offer://?credential_offer_uri=
  https://keycloak.example/realms/myrealm/protocol/oid4vc/credential-offer/abc123
```

Offer contains:
- `credential_issuer` — Keycloak realm URL
- `credential_configuration_ids` — which credentials
- `grants.pre-authorized_code` — one-time code
- Code expires after **5 minutes**

<!--
The credential offer URI uses a custom scheme so the wallet app can intercept it. The pre-authorized code is single-use and short-lived for security.
-->

---

# OID4VCI — Additional Measures & Alternatives

**`tx_code`** — The issuer can require a PIN (transaction code) that the user must enter in the wallet before the credential is issued. Prevents unauthorized use of intercepted credential offers.

**Authorization Code Flow** — The wallet initiates issuance itself: discovers issuer metadata, starts an OAuth 2.0 authorization request with PKCE, and exchanges the resulting code for an access token. How the user authenticates is up to the authorization server.

<!--
tx_code adds an extra layer of security — even if someone intercepts a QR code, they can't claim the credential without the PIN. The Authorization Code Flow is the alternative to pre-authorized code — the wallet initiates the process instead of scanning a QR code from an already-authenticated session. How the user authenticates during the authorization step is independent of OID4VCI — for example, the German PID provider uses eID card authentication via NFC, but that's an implementation detail of the authorization server, not part of the OID4VCI spec.
-->

---

<!-- _class: lead -->

# Credential Presentation
## OID4VP Deep Dive

---

# OID4VP — The Verification Protocol

A verifier needs to:
1. **Request** specific credentials and claims
2. **Authenticate** itself to the wallet
3. **Receive** the response securely
4. **Verify** the credential is valid and trustworthy

Each of these involves specific standards and mechanisms.

<!--
Let's go through each of these steps in detail. This is where most of the complexity lives.
-->

---

<style scoped>
.mermaid { margin: -80px 0 -40px 0; }
</style>

# OID4VP — Full Flow (Pass by Reference)

<div class="mermaid">
sequenceDiagram
    participant U as User/Browser
    participant V as Verifier
    participant W as Wallet
    U->>V: Trigger wallet login
    V->>U: openid4vp://?request_uri=...&client_id=...
    U->>W: Open wallet
    W->>V: Fetch request_uri
    V->>W: Signed request object JWT
    W->>W: Verify signature, show consent
    W->>W: Encrypt response (ephemeral key)
    W->>V: POST /response (JWE vp_token)
    V->>V: Decrypt & verify
    V->>U: Login success
</div>

<!--
This is the complete OID4VP flow using pass by reference. Instead of embedding the full request in the URL, we only pass a request_uri — a short URL pointing to the signed request object. The wallet fetches the actual request from that URI. This is important because the request object can be quite large — it contains the DCQL query, client metadata with encryption keys, and the verifier's registration certificate. Putting all of that into a QR code or redirect URL would be impractical. The request_uri keeps the initial redirect small and clean.
-->

---

# OID4VP & SIOPv2 — Extending OAuth / OIDC

Two specs that work together on top of OAuth 2.0 / OIDC:

| Spec | What it adds | `response_type` |
|------|-------------|-----------------|
| **OID4VP** | Verifiable Presentations | `vp_token` |
| **SIOPv2** | Wallet as Self-Issued OP | `id_token` |
| **Both** | Combined | `vp_token id_token` |

- **SIOPv2** — the wallet acts as its own OpenID Provider, issuing `id_token`s signed with the holder's key (no central IdP needed)
- **OID4VP** — adds `vp_token` for presenting verifiable credentials
- Both specs reuse the standard OAuth 2.0 authorization request/response flow
- HAIP / EUDI ecosystem primarily uses **`vp_token`** only

<!--
These two specs are companions. SIOPv2 — Self-Issued OpenID Provider version 2 — turns the wallet into its own identity provider. Instead of redirecting to Google or GitHub, the wallet itself issues an id_token signed with the holder's key. OID4VP builds on top of this and adds the vp_token response type for presenting verifiable credentials. You can use them independently or together. When combined, the verifier gets both a self-issued id_token and a verifiable presentation in one response. In the EUDI ecosystem, we almost exclusively use vp_token alone because the credential itself carries all the identity information we need. But SIOPv2 is relevant when you want a wallet-level identity assertion — for example to correlate the wallet instance itself across sessions.
-->

---

# DCQL — Digital Credentials Query Language

JSON-based query replacing `presentation_definition` — describes **what** the verifier needs:

```json
{
  "credentials": [{
    "id": "pid_credential",
    "format": "dc+sd-jwt",
    "meta": { "vct_values": ["eu.europa.ec.eudi.pid.1"] },
    "claims": [
      { "path": ["family_name"] },
      { "path": ["given_name"] },
      { "path": ["birthdate"] }
    ]
  }]
}
```

Wallet decides **which** credentials satisfy the query.

<!--
DCQL is the new way to express what credentials and claims you want from the wallet. This query asks for a PID credential in SD-JWT format, specifically requesting family name, given name, and birthdate. The wallet will only disclose these specific claims thanks to selective disclosure. It's much cleaner than the old presentation_definition format.
-->

---

# Client Authentication — Client Identifier Prefixes

How does the wallet know **who** is asking for credentials?

| Prefix | client_id format | Trust basis |
|--------|-----------------|-------------|
| *(none)* | `https://example.com` | Pre-registration |
| `x509_san_dns` | `x509_san_dns:example.com` | X.509 certificate |
| `x509_hash` | `x509_hash:<base64url(sha256)>` | Certificate fingerprint |
| `verifier_attestation` | `verifier_attestation:<sub>` | Attestation JWT in request |

<!--
The client identifier prefix tells the wallet how to verify the verifier's identity. Pre-registered clients use their client_id without any prefix. HAIP mandates support for both x509_san_dns and x509_hash.
-->

---

# x509_san_dns — How It Works

1. Verifier has an X.509 certificate with DNS SAN
2. Request object JWT includes certificate in `x5c` header
3. Wallet extracts DNS SAN from certificate
4. Verifies: SAN matches `client_id`, signature is valid

```java
// Computing the client_id from certificate
X509Certificate cert = parsePemCertificate(pemCertificate);
String dnsSan = cert.getSubjectAlternativeNames()
    .stream()
    .filter(san -> (Integer) san.get(0) == 2) // DNS type
    .map(san -> (String) san.get(1))
    .findFirst().orElseThrow();
return "x509_san_dns:" + dnsSan;
```

<!--
This is the scheme we use in production. The verifier's TLS certificate serves double duty — it proves domain ownership AND authenticates the authorization request.
-->

---

# EUDI Wallet: Registration Certificate

The wallet needs to know it can trust the verifier. A **Registration Certificate** (`rc-rp+jwt`) is issued by a national Trust Anchor, proving the verifier is authorized.

```json
{
  "typ": "rc-rp+jwt",
  "sub": "https://verifier.example.com",
  "service": "Identity Verification Service",
  "privacy_policy": "https://verifier.example.com/privacy",
  "credentials": [{
    "format": "dc+sd-jwt",
    "vct": "eu.europa.ec.eudi.pid.1",
    "claims": ["given_name", "family_name", "birthdate"]
  }],
  "public_body": false
}
```

Included in the request as `verifier_info`. Wallet enforces: verifier can only request what's listed.

<!--
Registration certificates are the verifier equivalent of trust lists for issuers. They explicitly list which credentials and claims the verifier is allowed to request. The wallet displays this to the user before they consent, and can reject requests that exceed what's registered.
-->

---

# Holder Binding & Request Binding

Two things a verifier must prove about a presentation:

| | **Holder Binding** | **Request Binding** |
|---|---|---|
| **Question** | Is the presenter the credential owner? | Is this response for *my* request? |
| **SD-JWT** | KB-JWT signed with `cnf.jwk` key | KB-JWT contains `aud`, `nonce`, `sd_hash` |
| **mDOC** | `DeviceAuth` signed with holder key | `SessionTranscript` (deterministic CBOR) |

**SD-JWT** combines both in a single **KB-JWT**.
**mDOC** separates them — `DeviceAuth` for holder binding, `SessionTranscript` for request binding.

The session transcript is computed independently by both sides from protocol state (`nonce`, `client_id`, `response_uri`) — no shared secret needed.

<!--
Every credential presentation must prove two things. First, holder binding: the person presenting the credential is actually the person it was issued to. Second, request binding: the response is tied to a specific verifier request, preventing replay attacks. SD-JWT elegantly combines both in a single Key Binding JWT — the signature proves holder binding, while the aud, nonce, and sd_hash fields provide request binding. mDOC takes a different approach and separates these concerns. DeviceAuth is signed with the holder key embedded in the MSO to prove holder binding. The session transcript is a deterministic CBOR structure that both the wallet and verifier compute independently from protocol state to provide request binding.
-->

---

# Key Binding JWTs — The Chain of Trust

**Problem:** How does the verifier know the *presenter* owns the credential?

```
Issuer                        Wallet                      Verifier
  │                              │                            │
  │  1. Embed holder public key  │                            │
  │     in credential (cnf.jwk)  │                            │
  │  ───────────────────────►    │                            │
  │                              │  2. Sign KB-JWT with       │
  │                              │     holder private key     │
  │                              │  ──────────────────────►   │
  │                              │                            │
  │                              │  3. Extract cnf.jwk from   │
  │                              │     credential, verify     │
  │                              │     KB-JWT signature       │
```

**KB-JWT:** `aud`, `nonce`, `iat`, `sd_hash` (binds to credential + disclosed claims). **Verify:** extract `cnf.jwk` → check signature → check `sd_hash`, `aud`, `nonce`, `iat`

<!--
This is the chain of trust for key binding. The issuer embeds the holder's public key in the credential's cnf claim. When presenting, the wallet signs a Key Binding JWT. The verifier extracts the public key from the credential — trusted via the trust list — and verifies the KB-JWT signature. The sd_hash is computed over the entire SD-JWT presentation string, binding the proof to both the credential and the exact set of disclosed claims. Without this, anyone who copies a credential could present it.
-->

---

# mDOC DeviceAuth — The Chain of Trust

**Problem:** How does the verifier know the *presenter* owns the credential?

```
Issuer                        Wallet                      Verifier
  │                              │                            │
  │  1. Embed holder public key  │                            │
  │     in MSO (DeviceKeyInfo)   │                            │
  │  ───────────────────────►    │                            │
  │                              │  2. Sign DeviceAuth with   │
  │                              │     holder private key     │
  │                              │  ──────────────────────►   │
  │                              │                            │
  │                              │  3. Extract holder key     │
  │                              │     from issuer-signed     │
  │                              │     MSO, verify DeviceAuth │
```

mDOC calls this the "device key" — it's the wallet's holder key stored in `DeviceKeyInfo`.
**Verify:** validate issuer signature on MSO → extract holder key → check `DeviceAuth` signature

<!--
This is the mDOC equivalent of the KB-JWT chain of trust. The issuer embeds the holder's public key in the Mobile Security Object during credential issuance — mDOC calls this the "device key" because the spec assumes the key lives on the device's secure hardware. The MSO itself is signed by the issuer. When presenting, the wallet signs a DeviceAuth structure — a COSE signature over the SessionTranscript and DocType — using the holder's private key. The verifier first validates the issuer's signature on the MSO via the trust list, then extracts the holder key and verifies the DeviceAuth signature. The SessionTranscript is computed deterministically by both sides from protocol state, so it also provides request binding. Unlike SD-JWT where the KB-JWT combines holder binding and request binding, mDOC separates them — DeviceAuth for holder binding, SessionTranscript for request binding.
-->

---

# HAIP — Response Modes & Interoperability Profile

HAIP narrows down OID4VP options for EU-wide interoperability:

| Area | HAIP Requirement |
|------|-----------------|
| **Signatures** | ES256 (ECDSA with P-256) only |
| **Response mode** | `direct_post.jwt` or `dc_api.jwt` (encrypted) |
| **Encryption** | ECDH-ES with P-256, A128GCM / A256GCM |
| **Client ID schemes** | `x509_san_dns` and `x509_hash` |
| **Credential formats** | SD-JWT VC (`dc+sd-jwt`) and mDOC |
| **Query language** | DCQL |

Legacy `direct_post` (unencrypted) exists but is **not HAIP-compliant**.

<!--
HAIP is critical because the OID4VP spec itself is very flexible — too flexible for a real ecosystem. Without HAIP, every implementer could make different choices about algorithms, response modes, and formats. HAIP narrows this down to a specific set that everyone must support. Think of it as the EU's "this is how we do it" profile. The .jwt response modes wrap everything in a JWE. Verifiers must support both A128GCM and A256GCM, wallets must support at least one — with A256GCM preferred.
-->

---

# Encryption with Ephemeral Keys

<div class="mermaid">
sequenceDiagram
    participant V as Verifier
    participant W as Wallet
    V->>V: Generate ephemeral EC P-256 key
    V->>W: Request with public key in client_metadata
    W->>W: Encrypt vp_token (ECDH-ES + A256GCM)
    W->>V: JWE response
    V->>V: Decrypt with stored private key
</div>

Fresh key pair per request → **forward secrecy**. Public key sent via `client_metadata.jwks`, encrypted response alg `ECDH-ES` + enc `A256GCM`.

<!--
Every authorization request gets its own ephemeral encryption key. The public half goes to the wallet in client_metadata, the private half stays in the server session. HAIP mandates ECDH-ES for key agreement with A256GCM for content encryption. This gives us forward secrecy — even if one key is compromised, other requests are unaffected.
-->

---

# Credential Verification — ETSI Trust Lists

How do we trust a credential? Fetch → Verify → Lookup → Validate:

1. Fetch trust list (signed JWT) from **Trust Anchor** URL
2. Look up issuer → get their **X.509 certificate**
3. Verify the credential's signature against that certificate

```json
{ "trusted_entities": [{
    "entity_id": "https://pid-issuer.bundesdruckerei.de",
    "entity_name": "Bundesdruckerei PID Issuer",
    "trust_services": [{
      "type": "pid-issuance", "status": "granted",
      "x5c": ["MIIBjTCCATOgAwIBAgIUQ8..."]
    }]
}] }
```

Only a **single root certificate** needs to be trusted — the trust anchor's.

<!--
Trust lists are the backbone of the EUDI trust model. Published by trust anchors — typically national authorities — they list all authorized issuers with their X.509 certificates. When we receive a credential, we look up the issuer's entity_id in the trust list, extract the certificate, and verify the credential's signature. The trust list itself is signed by the trust anchor.
-->

---

# Disclosure Verification

## SD-JWT: `_sd` digest matching
- Each disclosure: `base64url([salt, claim_name, claim_value])`
- Verifier computes `base64url(SHA-256(disclosure))` for each
- Checks computed digest exists in credential's `_sd` array
- Reject on: duplicate digests, reserved names (`_sd`, `...`), malformed arrays

## mDOC: `ValueDigests`
- MSO contains per-element digests grouped by namespace
- Verifier computes SHA-256 of each `IssuerSignedItem`
- Checks computed digest matches MSO entry for that element

<!--
For SD-JWTs, the verifier takes each received disclosure, computes its SHA-256 hash, and looks it up in the _sd array of the issuer-signed credential. This proves each disclosed claim was part of the original credential without revealing undisclosed claims. For mDOC, the Mobile Security Object contains per-element digests — the verifier recomputes them from the received IssuerSignedItems and checks they match.
-->

---

# SD-JWT Disclosures

**Object properties** — 3-element array: `[salt, claim_name, claim_value]`

```
Disclosure:    WyJfc0kiLCAiZ2l2ZW5fbmFtZSIsICJFcmlrYSJd
Decoded:       ["_sI", "given_name", "Erika"]
SHA-256:       base64url(SHA-256("WyJfc0ki...")) → "kL2g...9xYU"  ← matches _sd entry
```

Credential payload:
```json
{ "_sd": ["H0wL...dGFi", "kL2g...9xYU"], "_sd_alg": "sha-256" }
```

**Array elements** — 2-element array: `[salt, value]` (no claim name needed)
Referenced via `{"...": "<digest>"}` entries in the credential's JSON arrays.

<!--
Each disclosure is a base64url-encoded JSON array. For object properties it has three elements: salt, claim name, and value. For array elements, only two: salt and value — the position in the array replaces the need for a name. The verifier hashes the raw base64url string and checks the digest against the _sd array or the three-dot entries. The salt ensures identical values produce different digests, preventing correlation.
-->

---

# Credential Revocation — Token Status Lists

Issuer publishes a **Token Status List** (`statuslist+jwt`) — DEFLATE-compressed byte array, multi-bit entries:

| Bits | Status values | Example |
|------|--------------|---------|
| 1 | VALID / INVALID | Simple revocation |
| 2 | + SUSPENDED | Most common |
| 8 | Up to 256 statuses | Application-specific |

**Verification:** Credential contains `{ "status_list": { "idx": 42, "uri": "..." } }`
→ Fetch list → decompress → read bits at index 42

**Privacy-preserving:** verifier fetches **entire list**, issuer can't tell which credential is checked.

<!--
The Token Status List is a compact byte array distributed as a signed JWT. The verifier fetches the whole list, decompresses it, and reads the bits at the credential's index. Multi-bit entries let you distinguish between revoked and suspended. Because the entire list is fetched, the issuer has no way to know which specific credential is being checked — this is a deliberate privacy feature.
-->

---

<!-- _class: lead -->

# Integrating OID4VP into Keycloak

---

# Architecture Overview

```
  User/Browser            EUDI Wallet
       │                       │
       ▼                       │
  ┌──────────┐                 │
  │ Keycloak │                 │
  └────┬─────┘                 │
       ▼                       │
  ┌──────────────────┐         │
  │  OID4VP Identity │◄───────►│
  │  Provider (SPI)  │         │
  └────────┬─────────┘
           ▼
  ┌──────────────────┐    ┌────────────────┐
  │   Credential     │───►│  Trust List    │
  │   Verifier       │    │  Service       │
  └──────────────────┘    └────────────────┘
```

<!--
Here's the big picture. We implemented the OID4VP verifier as a Keycloak Identity Provider using the broker SPI. This lets Keycloak treat wallet authentication just like any other external identity provider — like Google or GitHub login. The verifier component handles the cryptographic verification and consults trust lists to validate issuer certificates.
-->

---

# Identity Provider SPI

```java
public class Oid4vpIdentityProvider
    extends AbstractIdentityProvider<Oid4vpIdentityProviderConfig> {

    // Three authentication flows:
    // 1. DC API — W3C Digital Credentials API (Chrome)
    // 2. Same-device — HTTP redirect to wallet app
    // 3. Cross-device — QR code scanning
}
```

- Registered as a standard Keycloak IdP
- Configurable via Keycloak Admin UI
- Supports mapper-based claim extraction
- Session state management for security (nonce, encryption keys)

<!--
The identity provider SPI is the natural extension point in Keycloak for adding new authentication methods. Our implementation supports three different flows to handle different device scenarios.
-->

---

# Auto-Generating DCQL from Mappers

Configure **IdP mappers** in Admin UI — `DcqlQueryBuilder` generates the query automatically:

```
Mapper 1: SD-JWT / eu.europa.ec.eudi.pid.1 / family_name
Mapper 2: SD-JWT / eu.europa.ec.eudi.pid.1 / given_name
Mapper 3: SD-JWT / eu.europa.ec.eudi.pid.1 / birthdate
```
↓ generates ↓
```json
{ "credentials": [{
    "id": "cred1", "format": "dc+sd-jwt",
    "meta": { "vct_values": ["eu.europa.ec.eudi.pid.1"] },
    "claims": [{ "path": ["family_name"] },
               { "path": ["given_name"] },
               { "path": ["birthdate"] }]
}] }
```

Admins don't need to understand DCQL — configure mappers like any other IdP.

<!--
This is one of the nicest features of our implementation. The builder groups mappers by format and credential type, deduplicates, and produces a clean DCQL query. For mDOC credentials, it also handles the namespace-qualified claim paths. If you need full control, you can still provide an explicit DCQL query.
-->

---

# Client-Side: W3C Digital Credentials API

```javascript
const credential = await navigator.credentials.get({
  digital: {
    requests: [{
      protocol: "openid4vp-v1-signed",
      data: { request: requestObjectJwt }
    }]
  }
});
```

- Native browser API — no redirects, no QR codes
- Browser mediates wallet selection
- Best user experience for web-based verification

<!--
The Digital Credentials API is the future of wallet interaction on the web. The browser handles the wallet selection UI, similar to how WebAuthn works for passkeys. We provide a signed request object JWT, and the browser handles the rest. There's also an unsigned variant using protocol "openid4vp-v1-unsigned" where the request data is passed directly instead of as a JWT.
-->

---

# DC API — Browser Support & Pitfalls

| Browser | Version | Status |
|---------|---------|--------|
| **Chrome** | 141+ (Sept 2025) | Shipped — `openid4vp-v1-signed` / `unsigned` |
| **Safari** | 26+ (Sept 2025) | `org-iso-mdoc` only — **no OpenID4VP!** |
| **Firefox** | — | Negative standards position |

**Key pitfalls:**
- **Protocol fragmentation** — must implement dual protocols for Chrome + Safari
- API changed: `navigator.identity.get()` → `navigator.credentials.get()`, `providers` → `requests`
- Trust verification is **your responsibility** — the browser doesn't verify issuers
- Feature detection: `typeof DigitalCredential !== "undefined"`

<!--
Chrome shipped the DC API in version 141, not 128 which was just an origin trial. Safari supports the API but only for mdoc — no OpenID4VP at all. Firefox has a negative standards position. This fragmentation is a real challenge. If your users might be on Safari, you need to implement the ISO mdoc protocol as well. And importantly, the browser doesn't verify trust — you still need your own trust list validation.
-->

---

# Fallback: Same-Device & Cross-Device Flows

Our login page supports all three flows, each toggleable in IdP config:

1. **DC API** — try first if `DigitalCredential` available
2. **Same-device redirect** — fallback on mobile
3. **Cross-device QR code** — fallback on desktop

```
openid4vp://?client_id=x509_san_dns:example.com
  &request_uri=https://example.com/request/abc123
```

Same URL used as redirect (mobile) or encoded as QR code (desktop).
Both fallbacks use `direct_post.jwt` response mode.

<!--
For browsers that don't support the DC API, we fall back to redirects on mobile or QR codes for cross-device scenarios. The login page detects browser capabilities and presents the appropriate option. DC API is preferred when available because it's the smoothest UX, but the fallbacks are always there.
-->

---

<!-- _class: lead -->

# Special Case
## Authenticating with the German PID

---

# The Problem: No Identifying Claim

The German PID (Person Identification Data) contains:
- `family_name`, `given_name`, `birthdate`
- `nationality`, `age_over_18`, ...

**But no unique identifier!** No `id`, no `subject`, no `personal_id`.

How do you link a PID to a Keycloak user account?

<!--
This was our biggest challenge. Unlike a passport number or social security number, the German PID has no claim that uniquely identifies a person. Name plus birthdate isn't unique either — think about common names and shared birthdays.
-->

---

# Solution: Issue Our Own Credential

Issue a custom `login-credential` containing `user_id` + `linked_at`, query **both** PID and our credential in one request.

<div class="mermaid">
sequenceDiagram
    participant U as User
    participant KC as Keycloak
    participant W as Wallet
    U->>KC: Present PID only
    KC->>U: "No account linked. Please log in."
    U->>KC: Username + Password
    KC->>KC: Issue login-credential
    KC->>U: QR code for credential offer
    U->>W: Scan and store credential
</div>

<!--
Our solution is to issue a supplementary credential that contains the Keycloak user ID. On first login, the user presents their PID but we can't match it to an account. So we ask them to authenticate with existing credentials, then issue a login credential that gets stored in their wallet alongside the PID.
-->

---

# Phase 2 — Returning Login

<div class="mermaid">
sequenceDiagram
    participant U as User
    participant KC as Keycloak
    participant W as Wallet
    U->>KC: Start wallet login
    KC->>W: DCQL: PID + login-credential
    W->>KC: Both credentials
    KC->>KC: Extract user_id from login-credential
    KC->>U: Logged in!
</div>

<!--
On subsequent logins, the wallet presents both credentials. We extract the user_id from our custom credential for a direct O(1) lookup. The PID is still verified to ensure the person hasn't changed, but the actual account binding comes from our credential.
-->

---

# DCQL with credential_sets

```json
{
  "credentials": [
    { "id": "german_pid", "format": "dc+sd-jwt",
      "meta": { "vct_values": ["eu.europa.ec.eudi.pid.1"] },
      "claims": [{ "path": ["family_name"] }, ...] },
    { "id": "login_cred", "format": "dc+sd-jwt",
      "meta": { "vct_values": ["login-credential"] },
      "claims": [{ "path": ["user_id"] }, ...] }
  ],
  "credential_sets": [{
    "purpose": "Login with German eID",
    "options": [
      ["german_pid", "login_cred"],
      ["german_pid"]
    ]
  }]
}
```

<!--
Here's where credential_sets become essential. We prefer both credentials — that's the fast path, direct login. But if the user doesn't have our login credential yet, the wallet falls back to presenting just the PID, which triggers the enrollment flow. One query handles both scenarios.
-->

---

# PID Binding — Re-Enrollment

What if the user loses their `login-credential`?

- Wallet only presents PID → **enrollment flow triggers again**
- User authenticates with username/password
- Previous federated identity is removed
- New credential issued, new identity linked

The `credential_sets` fallback handles this automatically.

<!--
This is the beauty of the credential_sets approach. Lost credential? No problem. The same query naturally falls back to the PID-only option, and the system re-enrolls the user. No special error handling needed.
-->

---

<!-- _class: lead -->

# Summary & Looking Ahead

---

# A Match Made in Heaven? — Yes!

| OID4VP Requirement | Keycloak Foundation |
|---|---|
| Authorization Request (JAR) | **Identity Provider SPI** — natural extension point |
| DCQL query | **Mapper infrastructure** — claim extraction like any IdP |
| `direct_post.jwt` response | **REST endpoint** via realm resource provider |
| Response encryption | **Session management** — ephemeral keys fit naturally |
| SD-JWT / mDOC verification | **Realm key management** — keys already managed |
| Issuer trust validation | **Broker & Federation** — federated identity model |
| HAIP compliance | Single config toggle enforcing all requirements |

OID4VP and OID4VCI are built on OAuth 2.0 / OIDC — the very protocols Keycloak already implements.

<!--
To answer the title question: yes, it really is a match made in heaven. Every OID4VP requirement maps cleanly to an existing Keycloak SPI. The Identity Provider SPI handles the protocol flow, the mapper SPI handles claim extraction, authentication sessions store ephemeral state, and the Admin UI provides configuration. We didn't have to fight the framework; we extended it naturally.
-->

---

# A Match Made in Heaven? — Almost

**One caveat:** The IdP SPI assumes the external IdP response arrives via browser redirect — carrying session cookies.

But the wallet is a native app, not a browser — the `direct_post` response has no cookies.

Workarounds are needed to associate the wallet's response with the correct browser authentication session.

<!--
There is one notable friction point. Keycloak's Identity Provider SPI was designed for browser-based OAuth flows where the response comes back as a redirect carrying session cookies. The wallet is a native app — when it POSTs to the direct_post endpoint, there are no cookies. So we need workarounds to correlate the wallet's response with the right browser session. It's solvable, but it's the one place where the abstraction doesn't fit perfectly.
-->

---

# What We Built

- Full **OID4VP verifier** as Keycloak Identity Provider
- Support for **SD-JWT** and **mDOC** credentials
- Two authentication flows: **same-device** and **cross-device**
- **DCQL auto-generation** from IdP mappers
- **HAIP 1.0 compliant**: ES256, ECDH-ES + A128GCM/A256GCM, trust lists
- Solved **German PID** linking with supplementary credentials *(separate from extension)*

<!--
Let me summarize what we've built. It's a complete OID4VP integration that handles the full verification pipeline — from building the request to verifying the response and establishing a Keycloak session.
-->

---

# Current Status & Next Steps

**Where we are:**
- Testing in the **German EUDI Wallet Sandbox** with **Bundesdruckerei** reference wallet
- Validated against the **OIDF conformance tests**
- Preparing to use in a project for a German public services customer

**Where we're going:**
- **Release** the Keycloak extension on GitHub as open source
- **Reach out** to Keycloak maintainers and community
- Goal: contribute toward **integration into Keycloak Core**

<!--
We're testing against real wallet implementations in the German sandbox, and it's used in an actual customer project. Our ultimate goal is to make this part of Keycloak itself — we're planning to open source our implementation and work with the community.
-->

---

# Thank You!

<div class="columns">
<div>

**Dominik Schlosser**
![w:150](assets/dominik-placeholder.png)

**Tom Schneider**
![w:150](assets/tom-placeholder.png)

</div>
<div>

**Slides:**
![w:200](assets/slides-qr.png)
https://ric03.github.io/presentation-keycloak-eudi-wallet/

**Keycloak OID4VP Extension:**
https://github.com/ba-itsys/keycloak-extension-oid4vp

</div>
</div>

<!--
Thank you for your attention. You can find the slides via the QR code. The Keycloak OID4VP extension will be available on GitHub — we're happy to take questions about the technical details of the integration or the German PID workaround.
-->
