
this is a fork of vorp banking 

You can use these exports in other scripts (e.g., banking or salary systems) to interact with the CrimsonRP-Society data.

### 1. GetSocietyBalance
Returns the current treasury balance for a specific society.

**Usage:**
```lua
local balance = exports['crimsonrp-society']:GetSocietyBalance('sheriff')
print("Current balance: " .. balance)
```

---

### 2. PaySalaryToMember
Adds an amount to a character's unpaid salary tracking in the database.

**Usage:**
```lua
-- charIdentifier: The character's unique ID
-- amount: The amount to be added
exports['crimsonrp-society']:PaySalaryToMember(charIdentifier, amount)
```
### 3. GetUnpaidSalary
Returns the current amount of unpaid salary for a specific character.

**Usage:**
```lua
-- charIdentifier: The character's unique ID
local unpaidSalary = exports['crimsonrp-society']:GetUnpaidSalary(charIdentifier)
print("Unpaid salary: " .. unpaidSalary)
```
