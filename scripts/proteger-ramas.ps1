# =============================================================================
# Proteccion de ramas main y develop   [EP3 IE5]
# Ejecutar UNA vez desde PowerShell, en la carpeta del repo:
#     powershell -ExecutionPolicy Bypass -File scripts/proteger-ramas.ps1
# Requiere gh autenticado con la cuenta duena del repositorio.
#
# Reglas: no se puede hacer push directo (todo entra por pull request), los
# checks del pipeline deben estar en verde, no se permite force-push ni borrar
# la rama, y las conversaciones del PR deben quedar resueltas.
# =============================================================================
$repo = gh repo view --json nameWithOwner --jq .nameWithOwner
$checks = @(
  "Pruebas (JUnit + Cucumber + JaCoCo)",
  "SonarQube Cloud (Quality Gate)",
  "Imagen Docker (build + Trivy + GHCR)",
  "Orquestación Kubernetes (kind)",
  "Cumplimiento (Gitleaks + Trivy config + auditoria)",
  "Observabilidad (Prometheus + Grafana + alertas)"
)
$lista = ($checks | ForEach-Object { '"' + $_ + '"' }) -join ","
$json = @"
{
  "required_status_checks": { "strict": false, "contexts": [ $lista ] },
  "enforce_admins": false,
  "required_pull_request_reviews": { "required_approving_review_count": 0, "dismiss_stale_reviews": true },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
"@
$archivo = Join-Path $env:TEMP "proteccion-ramas.json"
[IO.File]::WriteAllText($archivo, $json)
foreach ($rama in @("main", "develop")) {
  Write-Host "Protegiendo $rama ..."
  gh api -X PUT "repos/$repo/branches/$rama/protection" --input $archivo | Out-Null
  gh api "repos/$repo/branches/$rama/protection" --jq "{rama: `"$rama`", checks: .required_status_checks.contexts, force_push: .allow_force_pushes.enabled, borrar: .allow_deletions.enabled}"
}
Remove-Item $archivo
