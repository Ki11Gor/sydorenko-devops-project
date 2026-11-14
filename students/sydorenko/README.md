# Study Planner API

API приймає кількість тем, денний ліміт і час на одну тему. Він повертає загальну тривалість та розклад. Наприклад, 10 тем по 25 хвилин із лімітом 3 на день займуть **4 дні й 250 хвилин**. На останній день залишиться одна тема.

| Маршрут | Результат |
| --- | --- |
| `GET /` | Назва API і приклад запиту |
| `GET /health` | `{"status":"ok"}` |
| `GET /api/plan?topics=10&perDay=3&minutes=25` | Кількість днів, загальна тривалість і розклад |

`topics` приймає цілі числа від 1 до 365, `perDay` від 1 до 50, `minutes` від 1 до 240. Якщо значення пропущено, повторено або воно поза межами, API повертає `400`.

## Локальний запуск

Відкрий термінал у `students/sydorenko` у клонованому репозиторії. Запусти Docker Desktop або Docker Engine.

```bash
docker build -t study-planner:local .
docker run --rm -d --name study-planner -p 127.0.0.1:3000:3000 study-planner:local
curl -fsS http://127.0.0.1:3000/health
curl -fsS 'http://127.0.0.1:3000/api/plan?topics=10&perDay=3&minutes=25'
docker stop study-planner
```

У Windows PowerShell можна використати `curl.exe` або відкрити URL у браузері. `PORT` задає порт застосунку всередині контейнера, за замовчуванням `3000`. Якщо змінюєш `PORT`, зміни також внутрішній порт у параметрі `-p`. Для запуску тестів без Docker установи Node.js 24 і виконай `npm ci`, потім `npm test`.

## Як працює CI/CD

Після `push` до `main` workflow запускає тести API, збирає образ за хешем коміту й перевіряє HTTP у контейнері. Паралельно Terraform перевіряє форматування, схему та `plan`/`apply` з підставним AWS-провайдером. Ці перевірки працюють без AWS-акаунта й Docker Hub.

З налаштованими секретами workflow публікує перевірений образ у Docker Hub під тегом коміту. Коли `ENABLE_EC2_DEPLOY` має значення `true`, Terraform застосовує план, створює EC2 і Security Group та передає IP інстанса кроку деплою. GitHub Actions тимчасово дозволяє SSH з IP runner, перевіряє публічний ключ сервера з журналу EC2, запускає опублікований образ за digest і перевіряє `/health`. Наприкінці крок видаляє тимчасове правило SSH.

Файл workflow розташований [у кореневій папці GitHub Actions](../../.github/workflows/study-planner.yml). Код API, Terraform і сценарій SSH лежать у `students/sydorenko`.

## Налаштування Docker Hub та AWS

Секрети додай у **Settings → Secrets and variables → Actions → Secrets**.

| Секрет | Значення |
| --- | --- |
| `DOCKER_USERNAME` | Ім’я Docker Hub. Створи в цьому акаунті публічний репозиторій `study-planner` |
| `DOCKER_TOKEN` | Docker Hub Personal Access Token із правом запису |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | Дані AWS для EC2 і доступу до S3 зі станом Terraform |
| `AWS_SESSION_TOKEN` | Додатковий токен, якщо AWS видав тимчасові облікові дані |
| `EC2_SSH_KEY_B64` | Приватний ключ від пари EC2 у Base64 одним рядком |

У WSL команда `base64 -w 0 devops-key.pem | clip.exe` копіює ключ у буфер Windows для вставлення в поле секрету. Приватний ключ і його Base64-подання зберігай поза Git.

| Змінна Actions | Значення |
| --- | --- |
| `AWS_REGION` | Регіон EC2 і бакета S3. За замовчуванням `us-east-1` |
| `TF_STATE_BUCKET` | Наявний приватний бакет S3 у тому самому регіоні. Стан зберігається за ключем `sydorenko-devops-project/study-planner.tfstate` |
| `EC2_KEY_NAME` | Точна назва наявної пари ключів EC2 у цьому регіоні |
| `APP_CIDR` | IPv4 CIDR, якому дозволено TCP 3000. Для перевірки зі свого ПК вкажи свою публічну IP-адресу з `/32` |
| `ENABLE_EC2_DEPLOY` | `true`, коли готові налаштування AWS і Docker Hub |

В AWS потрібні стандартний VPC із підмережею, пара ключів та приватний бакет S3. Для бакета ввімкни Block Public Access і версіонування. Обліковим даним потрібні дозволи керувати EC2 та Security Group, читати журнал інстанса, читати й записувати стан і створювати та видаляти файл блокування S3. Ці ресурси можуть створювати витрати в AWS. За першого запуску Ubuntu 24.04 установлює Docker через `infra/bootstrap.sh`.

Коли параметри готові, виконай `push` у `main` або запусти **Actions → Study Planner CI/CD → Run workflow → main**. У журналі **Provision and deploy on EC2** з’явиться `EC2 health check passed.`. Адресу застосунку можна взяти з `app_url` у вихідних значеннях Terraform.

## Видалення інфраструктури

Після перевірки вимкни `ENABLE_EC2_DEPLOY` і дочекайся завершення активного workflow. Для `destroy` використовуй той самий бакет, ключ стану, регіон і значення змінних, що й у GitHub Actions. З прикладом нижче працюй у Bash із налаштованими обліковими даними AWS.

```bash
cd infra
export AWS_DEFAULT_REGION=us-east-1
export TF_VAR_aws_region="$AWS_DEFAULT_REGION"
export TF_VAR_key_name=devops-key
export TF_VAR_app_cidr=203.0.113.10/32
export TF_STATE_BUCKET=your-private-state-bucket
terraform init -reconfigure \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="key=sydorenko-devops-project/study-planner.tfstate" \
  -backend-config="region=$AWS_DEFAULT_REGION" \
  -backend-config="encrypt=true" -backend-config="use_lockfile=true"
terraform destroy -lock-timeout=120s
```

Підстав свої значення замість демонстраційних і підтвердь `yes` після перегляду плану видалення. У EC2 перевір, що інстанс має статус `Terminated` і групу `study-planner` видалено.
