# Overlay prod

`sealed-jwt.yaml` (SealedSecret `propuestas-jwt`) se genera contra el cluster prod
con `scripts/seal-jwt.sh prod` (plan 010) y se descomenta en `kustomization.yaml`.
Solo se commitea el SealedSecret cifrado, nunca la llave privada.
