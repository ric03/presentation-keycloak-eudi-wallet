---
marp: true
theme: default
paginate: true
# theme: gaia
# backgroundColor: #fff
# backgroundImage: url('https://marp.app/assets/hero-background.svg')
---

# **Keycloak and EUDI-Wallet**

###  A match made in heaven?

---

Agenda

- What is the EUDI-Wallet?
- Specifications: `OpenIDVP` & `OpenIDVCI`
- Credential Types: `SD-JWT` and `mDOC`
- Keycloak: Current implementation status (`OpenIDVCI` & `SD-JWT`)
- Implementation ideas for VP
- Missing integrations: Trust List Service, OAuth Status List (for revocations)
- Demo

---

![bg 90% right](assets/eudi-wallet-smartphone-mockup.png)

# EU Digital Identity Wallet

- Authenticate
- Store
- Share
- Sign

<!-- footer: https://ec.europa.eu/digital-building-blocks/sites/spaces/EUDIGITALIDENTITYWALLET/pages/791609471/What+is+the+Wallet -->

---

# Specifications

## `OpenID4VCI`
- OpenID for **V**erifiable **C**redential **I**ssuance
- Protocol for requesting and presenting Credentials

## `OpenID4VP`
- OpenID for **V**erifiable **P**resentations
- API for the issuance of Verifiable Credentials


<!-- Reset footer, otherwise it will be shown on each following page -->
<!-- footer: "" -->

---

# Credential Types

## `SD-JWT`
- **S**elective **D**isclosure for **J**SON **W**eb **T**okens

## `mDOC`
- **M**obile **Doc**ument

---

# Thank you

Slides are available at
https://ric03.github.io/presentation-keycloak-eudi-wallet/