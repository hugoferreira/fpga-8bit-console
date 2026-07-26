## ADDED Requirements

### Requirement: Celeste Structured Address and Procedure Migration
The generated layout-owned Celeste modules SHALL exercise pool address
materialisation and procedure declarations without editing `src/celeste/`.
Each migrated construct SHALL have an exact expected count and retain the
current machine bytes.

#### Scenario: Object pointer routine is migrated
- **WHEN** the generated object module is prepared
- **THEN** the existing object-address routine is expressed through a typed
  pool address operation and a scoped procedure parameter contract

#### Scenario: Full game is rebuilt
- **WHEN** indexed, pool and procedure frontend support is enabled in the
  Celeste layout build
- **THEN** the resulting 65,536-byte ROM is byte-for-byte identical to the
  direct current source
