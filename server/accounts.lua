-- Credential-based app accounts: rows keyed by username with a salted
-- SHA-256 password (hashed in MySQL via SHA2 — game-grade auth, not banking).
-- crimeapp_sessions maps a character (citizenid) to the account it is logged
-- into, so login persists across relogs until Sign out.
--
-- Migration: the original schema keyed accounts by citizenid with no
-- password. On boot we detect that shape and migrate in place: existing
-- accounts keep their points/settings, stay logged in via a session row, and
-- have NO password yet — their first login (or Reset password) claims one.

Accounts = {}
local cache = {} -- citizenid -> resolved account row | false (known logged-out)

local SALT_CHARS = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
local function randomSalt()
    local out = {}
    for i = 1, 12 do
        local n = math.random(1, #SALT_CHARS)
        out[i] = SALT_CHARS:sub(n, n)
    end
    return table.concat(out)
end

local function normalizeRow(row)
    if not row then return nil end
    row.subscribed = row.subscribed == 1 or row.subscribed == true
    row.points = row.points or 0
    return row
end

function Accounts.EnsureTable()
    CreateThread(function()
        while GetResourceState('oxmysql') ~= 'started' do Wait(200) end
        local ok, err = pcall(function()
            MySQL.query.await([[
                CREATE TABLE IF NOT EXISTS crimeapp_accounts (
                    username      VARCHAR(20)  NOT NULL PRIMARY KEY,
                    password_hash VARCHAR(64)  DEFAULT NULL,
                    salt          VARCHAR(16)  DEFAULT NULL,
                    avatar_url    VARCHAR(255) DEFAULT NULL,
                    points        INT          NOT NULL DEFAULT 0,
                    subscribed    TINYINT(1)   NOT NULL DEFAULT 1,
                    created_at    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
                )]])
            MySQL.query.await([[
                CREATE TABLE IF NOT EXISTS crimeapp_sessions (
                    citizenid VARCHAR(50) NOT NULL PRIMARY KEY,
                    username  VARCHAR(20) NOT NULL,
                    logged_at TIMESTAMP   DEFAULT CURRENT_TIMESTAMP
                )]])

            -- Pre-password schema? (accounts keyed by citizenid)
            local old = MySQL.query.await("SHOW COLUMNS FROM crimeapp_accounts LIKE 'citizenid'")
            if old and old[1] then
                MySQL.query.await("ALTER TABLE crimeapp_accounts ADD COLUMN password_hash VARCHAR(64) DEFAULT NULL, ADD COLUMN salt VARCHAR(16) DEFAULT NULL")
                MySQL.query.await("INSERT IGNORE INTO crimeapp_sessions (citizenid, username) SELECT citizenid, username FROM crimeapp_accounts")
                MySQL.query.await("ALTER TABLE crimeapp_accounts DROP PRIMARY KEY, DROP COLUMN citizenid, ADD PRIMARY KEY (username)")
                print('^3[noted_crimeapp]^0 migrated accounts to credential schema — existing users stay logged in and claim a password on first login/reset')
            end
        end)
        if ok then
            print('^2[noted_crimeapp]^0 accounts + sessions tables ready')
        else
            print(('^1[noted_crimeapp]^0 FAILED preparing account tables: %s'):format(tostring(err)))
        end
    end)
end

-- Resolve the account a character is logged into (nil = logged out).
function Accounts.Get(citizenid)
    if not citizenid then return nil end
    if cache[citizenid] ~= nil then return cache[citizenid] or nil end
    local row = MySQL.single.await([[
        SELECT a.username, a.avatar_url, a.points, a.subscribed
        FROM crimeapp_sessions s
        JOIN crimeapp_accounts a ON a.username = s.username
        WHERE s.citizenid = ?]], { citizenid })
    cache[citizenid] = normalizeRow(row) or false
    return cache[citizenid] or nil
end

function Accounts.UsernameTaken(username)
    local row = MySQL.single.await('SELECT 1 AS x FROM crimeapp_accounts WHERE LOWER(username) = LOWER(?)', { username })
    return row ~= nil
end

local function validPassword(password)
    local lim = Config.Limits.password
    if type(password) ~= 'string' or #password < lim.min or #password > lim.max then
        return false, ('Password must be %d–%d characters.'):format(lim.min, lim.max)
    end
    return true
end

function Accounts.Create(citizenid, username, password, avatar)
    if not citizenid then return false, 'No character.' end
    username = tostring(username or ''):gsub('^%s+', ''):gsub('%s+$', '')
    local lim = Config.Limits.username
    if #username < lim.min or #username > lim.max then
        return false, ('Username must be %d–%d characters.'):format(lim.min, lim.max)
    end
    if not username:match('^[%w_%.]+$') then
        return false, 'Username may only contain letters, numbers, _ and .'
    end
    local okPw, pwErr = validPassword(password)
    if not okPw then return false, pwErr end
    if Accounts.UsernameTaken(username) then return false, 'That username is taken.' end

    local subscribed = Config.Notifications.defaultSubscribed and 1 or 0
    local salt = randomSalt()
    local okInsert, insErr = pcall(function()
        MySQL.insert.await(
            'INSERT INTO crimeapp_accounts (username, password_hash, salt, avatar_url, points, subscribed) VALUES (?, SHA2(CONCAT(?, ?), 256), ?, ?, 0, ?)',
            { username, salt, password, salt, avatar, subscribed })
        MySQL.query.await('REPLACE INTO crimeapp_sessions (citizenid, username) VALUES (?, ?)', { citizenid, username })
    end)
    if not okInsert then
        print(('^1[noted_crimeapp]^0 account insert failed for %s: %s'):format(citizenid, tostring(insErr)))
        return false, 'That username is taken.' -- almost always a UNIQUE(username) race
    end

    cache[citizenid] = normalizeRow({
        username = username, avatar_url = avatar, points = 0, subscribed = subscribed,
    })
    return true
end

function Accounts.Login(citizenid, username, password)
    if not citizenid then return false, 'No character.' end
    if type(username) ~= 'string' or username == '' then return false, 'Enter a username.' end
    if type(password) ~= 'string' or password == '' then return false, 'Enter a password.' end

    local row = MySQL.single.await([[
        SELECT username, avatar_url, points, subscribed, password_hash,
               (password_hash IS NULL OR password_hash = SHA2(CONCAT(IFNULL(salt, ''), ?), 256)) AS pw_ok
        FROM crimeapp_accounts WHERE LOWER(username) = LOWER(?)]], { password, username })
    if not row then return false, 'Account not found.' end
    if not (row.pw_ok == 1 or row.pw_ok == true) then return false, 'Wrong password.' end

    -- Migrated (passwordless) account: this login claims the password.
    if row.password_hash == nil then
        local okPw, pwErr = validPassword(password)
        if not okPw then return false, pwErr end
        local salt = randomSalt()
        MySQL.update.await('UPDATE crimeapp_accounts SET salt = ?, password_hash = SHA2(CONCAT(?, ?), 256) WHERE username = ?',
            { salt, salt, password, row.username })
    end

    MySQL.query.await('REPLACE INTO crimeapp_sessions (citizenid, username) VALUES (?, ?)', { citizenid, row.username })
    row.password_hash, row.pw_ok = nil, nil
    cache[citizenid] = normalizeRow(row)
    return true
end

function Accounts.Logout(citizenid)
    if not citizenid then return end
    MySQL.update('DELETE FROM crimeapp_sessions WHERE citizenid = ?', { citizenid })
    cache[citizenid] = false
end

function Accounts.ChangePassword(citizenid, current, new)
    local acc = Accounts.Get(citizenid)
    if not acc then return false, 'Not signed in.' end
    local okPw, pwErr = validPassword(new)
    if not okPw then return false, pwErr end

    local row = MySQL.single.await([[
        SELECT (password_hash IS NULL OR password_hash = SHA2(CONCAT(IFNULL(salt, ''), ?), 256)) AS pw_ok
        FROM crimeapp_accounts WHERE username = ?]], { tostring(current or ''), acc.username })
    if not row or not (row.pw_ok == 1 or row.pw_ok == true) then
        return false, 'Current password is wrong.'
    end

    local salt = randomSalt()
    MySQL.update.await('UPDATE crimeapp_accounts SET salt = ?, password_hash = SHA2(CONCAT(?, ?), 256) WHERE username = ?',
        { salt, salt, new, acc.username })
    return true
end

-- Points/settings are per ACCOUNT (username). Crediting by name lets the
-- author earn confirm points even while logged out or offline.
function Accounts.AddPointsByName(username, amount)
    if not username then return end
    MySQL.update('UPDATE crimeapp_accounts SET points = points + ? WHERE username = ?', { amount, username })
    for _, acc in pairs(cache) do
        if acc and acc.username == username then
            acc.points = (acc.points or 0) + amount
        end
    end
end

function Accounts.AddPoints(citizenid, amount)
    local acc = Accounts.Get(citizenid)
    if not acc then return end
    Accounts.AddPointsByName(acc.username, amount)
end

function Accounts.LevelFor(points)
    points = points or 0
    local current, nextLevel
    for i = 1, #Config.Levels do
        local lvl = Config.Levels[i]
        if points >= lvl.points then current = lvl else nextLevel = nextLevel or lvl end
    end
    current = current or Config.Levels[1]
    return {
        name = current.name,
        nextName = nextLevel and nextLevel.name or nil,
        nextPoints = nextLevel and nextLevel.points or nil,
    }
end

function Accounts.SetSubscribed(citizenid, bool)
    local acc = Accounts.Get(citizenid)
    if not acc then return end
    acc.subscribed = bool and true or false
    MySQL.update('UPDATE crimeapp_accounts SET subscribed = ? WHERE username = ?', { bool and 1 or 0, acc.username })
end

Accounts.EnsureTable()
