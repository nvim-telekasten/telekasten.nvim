-- test_all.lua
-- Run all tests using the taglinks testing pattern

-- Colors for output
local function red(str)
    return "\27[31m" .. str .. "\27[0m"
end

local function green(str)
    return "\27[32m" .. str .. "\27[0m"
end

local function yellow(str)
    return "\27[33m" .. str .. "\27[0m"
end

print(yellow("\n=== Running Telekasten Tests ===\n"))

local all_passed = true
local results = {}

-- Test taglinks
print(yellow("Running taglinks tests..."))
local taglinks = require("telekasten.utils.taglinks")
local taglinks_ok, taglinks_err = pcall(taglinks._testme)
if taglinks_ok then
    print(green("✓ taglinks tests passed\n"))
    table.insert(results, { name = "taglinks", passed = true })
else
    print(red("✗ taglinks tests failed:"))
    print(red("  " .. tostring(taglinks_err) .. "\n"))
    all_passed = false
    table.insert(results, { name = "taglinks", passed = false })
end

-- Test telescope picker
print(yellow("Running telescope picker tests..."))
local telescope_test_ok, telescope_test_err = pcall(function()
    local telescope_test = require("telekasten.picker.telescope_test")
    return telescope_test._testme()
end)
if not telescope_test_ok then
    print(red("✗ telescope picker tests failed:"))
    print(red("  " .. tostring(telescope_test_err) .. "\n"))
    all_passed = false
    table.insert(results, { name = "telescope", passed = false })
else
    table.insert(results, { name = "telescope", passed = true })
end

-- Test fzf picker
print(yellow("Running fzf picker tests..."))
local fzf_test_ok, fzf_test_err = pcall(function()
    local fzf_test = require("telekasten.picker.fzf_test")
    return fzf_test._testme()
end)
if not fzf_test_ok then
    print(red("✗ fzf picker tests failed:"))
    print(red("  " .. tostring(fzf_test_err) .. "\n"))
    all_passed = false
    table.insert(results, { name = "fzf", passed = false })
else
    table.insert(results, { name = "fzf", passed = true })
end

-- Test snacks picker
print(yellow("Running snacks picker tests..."))
local snacks_test_ok, snacks_test_err = pcall(function()
    local snacks_test = require("telekasten.picker.snacks_test")
    return snacks_test._testme()
end)
if not snacks_test_ok then
    print(red("✗ snacks picker tests failed:"))
    print(red("  " .. tostring(snacks_test_err) .. "\n"))
    all_passed = false
    table.insert(results, { name = "snacks", passed = false })
else
    table.insert(results, { name = "snacks", passed = true })
end

-- Final summary
print("\n" .. string.rep("=", 60))
print(yellow("TEST SUMMARY"))
print(string.rep("=", 60))

local passed_count = 0
local failed_count = 0
for _, result in ipairs(results) do
    if result.passed then
        print(green("✓ " .. result.name))
        passed_count = passed_count + 1
    else
        print(red("✗ " .. result.name))
        failed_count = failed_count + 1
    end
end

print(string.rep("-", 60))
print(
    string.format(
        "%s: %d passed, %d failed, %d total",
        all_passed and green("PASSED") or red("FAILED"),
        passed_count,
        failed_count,
        passed_count + failed_count
    )
)
print(string.rep("=", 60) .. "\n")

if not all_passed then
    os.exit(1)
end
