# oyd-exercise-7-2 — Multi-Env Layout y GitHub Environment Promotion

Ejercicio 7.2 del curso **Optimizaciones y Desempeño — Cloud Deployment Automation**.

Pipeline de Terraform CD en GitHub Actions que separa la validación en checks
individuales sobre los pull requests, sube el `plan` como artifact, comenta el plan en el
PR y promueve de `dev` a `staging` con aprobación manual a través de los GitHub
Environments.

## Estructura del repositorio

```
.github/
└── workflows/
    └── terraform-cd.yml         # Workflow con 5 jobs
infra/
├── provider.tf                  # AWS provider + backend S3
├── main.tf                      # Recurso: aws_sqs_queue
├── variables.tf                 # aws_region, queue_name, visibility_timeout_seconds
└── envs/
    ├── dev/
    │   ├── dev.tfvars
    │   └── backend-dev.hcl
    └── staging/
        ├── staging.tfvars
        └── backend-staging.hcl
evidence/
└── pr-url.txt                   # URL del PR como evidencia
```

## Recurso provisionado

Una cola SQS por ambiente:

| Ambiente | `queue_name`             | `visibility_timeout_seconds` |
| -------- | ------------------------ | ---------------------------- |
| dev      | `exercise-queue-dev`     | 30 (default)                 |
| staging  | `exercise-queue-staging` | 60                           |

## Diseño del workflow

El workflow `terraform-cd.yml` define **exactamente 5 jobs**:

| Job                  | Trigger                  | Función                                                                 |
| -------------------- | ------------------------ | ----------------------------------------------------------------------- |
| `terraform-fmt`      | PR y push a `main`       | Corre `terraform fmt -check -recursive`                                 |
| `terraform-validate` | PR y push a `main`       | `terraform init -backend=false` + `terraform validate`                  |
| `terraform-plan`     | PR y push a `main`       | `init` con backend + `plan` + sube artifact `tfplan-dev` + comenta el PR |
| `apply-dev`          | Solo push a `main`       | Descarga el artifact y aplica con `terraform apply tfplan` (env: `dev`) |
| `apply-staging`      | Solo push a `main`       | Requiere aprobación manual (env: `staging`) y aplica en staging         |

### Por qué jobs separados

Antes los tres comandos (`fmt`, `validate`, `plan`) vivían en un solo job y un fallo
reportaba un único status check, sin indicar cuál check rompió. Al separarlos:

- Cada uno aparece como un status check individual en el PR.
- El reviewer ve exactamente dónde falló (formato, sintaxis o lógica del plan).
- `terraform-fmt` no necesita credenciales ni `init` → corre rapidísimo.
- `terraform-validate` corre con `-backend=false` → tampoco necesita credenciales AWS.
- `terraform-plan` es el único que toca AWS, sube el artifact y comenta el plan.

### Promoción `dev` → `staging`

`apply-dev` reusa el `tfplan` ya generado (no vuelve a planear) descargándolo con
`actions/download-artifact@v4`. Luego `apply-staging` declara `environment: staging`,
que es lo que dispara la pausa para **Required reviewers** configurada en el GitHub
Environment.

## Pre-requisitos

### Bucket S3 para el state

Se usa `pdds-oyd-tfstate-d0d13937` en `us-east-1`. Los archivos backend ya apuntan
ahí:

- `infra/envs/dev/backend-dev.hcl` → key `exercise-7-2/dev/terraform.tfstate`
- `infra/envs/staging/backend-staging.hcl` → key `exercise-7-2/staging/terraform.tfstate`

### Secrets del repositorio

En `Settings → Secrets and variables → Actions`:

| Secret                  | Valor          |
| ----------------------- | -------------- |
| `AWS_ACCESS_KEY_ID`     | Access key IAM |
| `AWS_SECRET_ACCESS_KEY` | Secret key IAM |
| `AWS_REGION`            | `us-east-1`    |

### GitHub Environments

En `Settings → Environments`:

1. **`dev`** — sin reglas de protección.
2. **`staging`** — activar **Required reviewers** y agregar al owner del repo como reviewer.

### Branch protection (opcional pero recomendado)

En `Settings → Branches → Add branch protection rule` para `main`:

- Require a pull request before merging
- Require status checks to pass: `terraform-fmt`, `terraform-validate`, `terraform-plan`

## Cómo verificar (Task 4)

1. Crear branch, hacer cambio trivial, abrir PR a `main`.
2. En el PR aparecen 3 status checks: `terraform-fmt`, `terraform-validate`, `terraform-plan`.
3. El job `terraform-plan` deja un comentario `### Terraform Plan — dev` con el output.
4. Al mergear, `apply-dev` corre automático; `apply-staging` queda en `Waiting` hasta aprobación manual.
5. Aprobar en `Actions → Run → Review deployments`.

La URL del PR queda guardada en `evidence/pr-url.txt`.

## Destruir todo

Cuando termine la evaluación:

```bash
cd infra
# Dev
terraform init -reconfigure -backend-config=envs/dev/backend-dev.hcl
terraform destroy -auto-approve -var-file=envs/dev/dev.tfvars

# Staging
terraform init -reconfigure -backend-config=envs/staging/backend-staging.hcl
terraform destroy -auto-approve -var-file=envs/staging/staging.tfvars
```
