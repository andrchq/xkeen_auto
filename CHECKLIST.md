# ✅ Чеклист перед публикацией на GitHub

## Файлы (всё готово ✓)

- [x] `install.sh` - Установочный скрипт
- [x] `xkeen_rotate.sh` - Основной скрипт ротации
- [x] `xkeen_sync.sh` - Скрипт синхронизации подписок
- [x] `README.md` - Основная документация
- [x] `INSTALL.md` - Инструкция по установке
- [x] `CHANGELOG.md` - История изменений
- [x] `GITHUB_SETUP.md` - Инструкция по загрузке на GitHub
- [x] `.gitignore` - Исключения для Git

## Действия перед публикацией

### 1. ⚠️ ОБЯЗАТЕЛЬНО: Замените YOUR_USERNAME

В следующих файлах замените `YOUR_USERNAME` на ваш GitHub username:

#### В `install.sh` (строка 11):
```bash
GITHUB_RAW="https://raw.githubusercontent.com/YOUR_USERNAME/xkeen_rotate/main"
```

#### В `README.md` (несколько мест):
```markdown
https://raw.githubusercontent.com/YOUR_USERNAME/xkeen_rotate/main/install.sh
https://github.com/YOUR_USERNAME/xkeen_rotate/issues
```

#### В `INSTALL.md` (2 места):
```markdown
https://raw.githubusercontent.com/YOUR_USERNAME/xkeen_rotate/main/install.sh
https://github.com/YOUR_USERNAME/xkeen_rotate/issues
```

### 2. Проверьте файлы

```bash
# Убедитесь что все скрипты имеют shebang
head -1 install.sh xkeen_rotate.sh xkeen_sync.sh
# Должно быть: #!/bin/sh

# Проверьте что токен и ID группы на месте (они общие для всех клиентов)
grep "TG_BOT_TOKEN\|TG_CHAT_ID" xkeen_rotate.sh
```

### 3. Создайте репозиторий на GitHub

1. Зайдите на https://github.com/new
2. Repository name: `xkeen_rotate`
3. Description: `Автоматическая ротация прокси-серверов для Xray/Xkeen`
4. Public
5. **НЕ добавляйте** README, .gitignore или license
6. Create repository

### 4. Загрузите файлы

#### Вариант A: Командная строка

```bash
cd "D:\Cursor Project\xkeen\xkeen_rotate"
git init
git add .
git commit -m "v1.0.0

Первая версия xkeen_rotate с автоматической ротацией серверов"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/xkeen_rotate.git
git push -u origin main
```

#### Вариант B: GitHub Desktop

1. File → Add Local Repository
2. Выберите папку проекта
3. Publish repository

### 5. Настройте репозиторий

#### Добавьте темы (Topics):
- xray
- openwrt
- proxy
- vpn
- automation
- telegram-bot
- entware
- shell-script

#### Добавьте описание:
"Автоматическая ротация прокси-серверов для Xray/Xkeen на роутерах OpenWRT"

#### Создайте релиз v1.0.0:
1. Releases → Create a new release
2. Tag: `v1.0.0`
3. Title: `v1.0.0 - Первая версия`
4. Описание из CHANGELOG.md
5. Publish release

### 6. Протестируйте установку

На роутере выполните:
```bash
curl -sSL https://raw.githubusercontent.com/YOUR_USERNAME/xkeen_rotate/main/install.sh | sh
```

### 7. Поделитесь ссылкой

Ваша команда для установки:
```bash
curl -sSL https://raw.githubusercontent.com/YOUR_USERNAME/xkeen_rotate/main/install.sh | sh
```

## Готово! 🎉

Теперь ваш проект доступен всем пользователям для установки одной командой!

## После публикации

- [ ] Протестируйте установку на чистом роутере
- [ ] Создайте GitHub Issues templates
- [ ] Добавьте GitHub Actions для автотестов (опционально)
- [ ] Напишите пост в сообществе OpenWRT
- [ ] Соберите feedback от пользователей

## Обновление в будущем

При внесении изменений:
```bash
git add .
git commit -m "v1.1.0 - Описание изменений"
git tag v1.1.0
git push origin main --tags
```

Создайте новый релиз на GitHub с описанием изменений из CHANGELOG.md

