-- lua/telekasten/picker/snacks_test.lua
-- Test functions for snacks picker (using taglinks testing pattern)

local M = {}

local function _print_debug(x, prefix)
    prefix = prefix or ""
    for k, v in pairs(x) do
        print(prefix .. k .. ": " .. tostring(v))
    end
end

local function _expect(x, y, context)
    for k, v in pairs(y) do
        if x[k] ~= v then
            if context then
                print("Test: " .. context)
            end
            print("expected:")
            _print_debug(y, "  ")
            print("got:")
            _print_debug(x, "  ")
            assert(false, "Test failed: " .. (context or "unknown"))
        end
    end
end

-- Test backend structure
M._test_backend_structure = function()
    local snacks = require("telekasten.picker.snacks")

    -- Test required functions exist
    assert(snacks.find_files ~= nil, "find_files missing")
    assert(snacks.live_grep ~= nil, "live_grep missing")
    assert(snacks.custom_picker ~= nil, "custom_picker missing")
    assert(snacks.setup ~= nil, "setup missing")

    -- Test actions exist
    assert(snacks.actions ~= nil, "actions table missing")
    assert(
        snacks.actions.select_default ~= nil,
        "select_default action missing"
    )
    assert(snacks.actions.close ~= nil, "close action missing")
    assert(
        snacks.actions.yank_selection ~= nil,
        "yank_selection action missing"
    )
    assert(
        snacks.actions.paste_selection ~= nil,
        "paste_selection action missing"
    )
    assert(snacks.actions.get_selection ~= nil, "get_selection action missing")
    assert(
        snacks.actions.get_current_line ~= nil,
        "get_current_line action missing"
    )

    -- Test themes exist
    assert(snacks.themes ~= nil, "themes table missing")
    assert(snacks.themes.dropdown ~= nil, "dropdown theme missing")
    assert(snacks.themes.ivy ~= nil, "ivy theme missing")
    assert(snacks.themes.cursor ~= nil, "cursor theme missing")

    print("✓ Backend structure tests passed")
end

-- Test actions functionality
M._test_actions = function()
    local snacks = require("telekasten.picker.snacks")

    -- Test get_selection with no selection
    snacks._current_selection = nil
    local result = snacks.actions.get_selection()
    assert(result == nil, "get_selection should return nil when no selection")

    -- Test get_selection with file selection
    snacks._current_selection = {
        file = "/test/path.md",
        text = "test text",
    }
    result = snacks.actions.get_selection()
    _expect(result, {
        value = "/test/path.md",
        filename = "/test/path.md",
    }, "get_selection with file")

    -- Test get_selection with text only
    snacks._current_selection = {
        text = "just text",
        value = "some value",
    }
    result = snacks.actions.get_selection()
    assert(result.value == "just text", "get_selection should prefer text")

    -- Test get_current_line
    snacks._current_line = nil
    result = snacks.actions.get_current_line()
    assert(result == "", "get_current_line should return empty string when nil")

    snacks._current_line = "test line"
    result = snacks.actions.get_current_line()
    assert(result == "test line", "get_current_line should return stored line")

    -- Cleanup
    snacks._current_selection = nil
    snacks._current_line = nil

    print("✓ Actions tests passed")
end

-- Test themes configuration
M._test_themes = function()
    local snacks = require("telekasten.picker.snacks")

    -- Test dropdown theme
    local dropdown = snacks.themes.dropdown()
    _expect(dropdown.layout, {
        height = 0.4,
        width = 0.6,
        position = "center",
    }, "dropdown theme layout")

    -- Test ivy theme
    local ivy = snacks.themes.ivy()
    _expect(ivy.layout, {
        height = 0.4,
        position = "bottom",
    }, "ivy theme layout")

    -- Test cursor theme
    local cursor = snacks.themes.cursor()
    _expect(cursor.layout, {
        height = 0.3,
        width = 0.3,
        position = "center",
    }, "cursor theme layout")

    -- Test theme merging
    local custom_dropdown = snacks.themes.dropdown({
        layout = { width = 0.8 },
    })
    assert(
        custom_dropdown.layout.width == 0.8,
        "theme should merge custom width"
    )
    assert(
        custom_dropdown.layout.height == 0.4,
        "theme should keep default height"
    )

    print("✓ Theme tests passed")
end

-- Test utilities
M._test_utilities = function()
    local snacks = require("telekasten.picker.snacks")

    -- Test supports
    assert(snacks.supports("live_grep") == true, "should support live_grep")
    assert(snacks.supports("themes") == true, "should support themes")
    assert(
        snacks.supports("media_preview") == false,
        "should not support media_preview"
    )
    assert(
        snacks.supports("nonexistent") == false,
        "should not support unknown feature"
    )

    -- Test create_entry_display
    local formatter = snacks.create_entry_display({})
    assert(
        type(formatter) == "function",
        "create_entry_display should return function"
    )

    -- Test formatter with string
    local result = formatter("test string")
    assert(result == "test string", "formatter should handle strings")

    -- Test formatter with table
    result = formatter({ display = "display text", value = "value" })
    assert(result == "display text", "formatter should use display field")

    result = formatter({ value = "some value" })
    assert(result == "some value", "formatter should fall back to value field")

    print("✓ Utility tests passed")
end

-- Test backend validation
M._test_validation = function()
    local snacks = require("telekasten.picker.snacks")
    local picker_init = require("telekasten.picker.init")

    local valid, err = picker_init.validate_backend(snacks)
    assert(
        valid == true,
        "snacks backend should pass validation: " .. (err or "")
    )

    print("✓ Validation tests passed")
end

-- Test plenary scandir integration
M._test_plenary_integration = function()
    local has_plenary, scandir = pcall(require, "plenary.scandir")
    assert(has_plenary, "plenary.scandir should be available")
    assert(scandir.scan_dir ~= nil, "scan_dir function should exist")

    -- Create temp test directory
    local test_dir = vim.fn.tempname()
    vim.fn.mkdir(test_dir, "p")

    -- Create test files
    local test_files = {
        "note1.md",
        "note2.md",
        "note3.txt",
    }

    for _, filename in ipairs(test_files) do
        local path = test_dir .. "/" .. filename
        local file = io.open(path, "w")
        if file then
            file:write("test content\n")
            file:close()
        end
    end

    -- Test scanning
    local files = scandir.scan_dir(test_dir, {
        search_pattern = ".*%.md$",
    })

    assert(files ~= nil, "scan_dir should return results")
    assert(#files == 2, "should find 2 .md files, found " .. #files)

    -- Cleanup
    vim.fn.delete(test_dir, "rf")

    print("✓ Plenary integration tests passed")
end

-- Test picker initialization
M._test_picker_init = function()
    local picker_init = require("telekasten.picker.init")

    -- Test setup with snacks
    picker_init.setup("snacks", {})
    assert(
        picker_init.get_backend() == "snacks",
        "backend should be set to snacks"
    )

    -- Test that functions are forwarded
    assert(picker_init.find_files ~= nil, "find_files should be forwarded")
    assert(picker_init.live_grep ~= nil, "live_grep should be forwarded")
    assert(
        picker_init.custom_picker ~= nil,
        "custom_picker should be forwarded"
    )

    print("✓ Picker initialization tests passed")
end

-- Main test runner
M._testme = function()
    print("\n=== Running Snacks Picker Tests ===\n")

    local tests = {
        { name = "Backend Structure", fn = M._test_backend_structure },
        { name = "Actions", fn = M._test_actions },
        { name = "Themes", fn = M._test_themes },
        { name = "Utilities", fn = M._test_utilities },
        { name = "Validation", fn = M._test_validation },
        { name = "Plenary Integration", fn = M._test_plenary_integration },
        { name = "Picker Initialization", fn = M._test_picker_init },
    }

    local passed = 0
    local failed = 0

    for _, test in ipairs(tests) do
        local ok, err = pcall(test.fn)
        if ok then
            passed = passed + 1
        else
            failed = failed + 1
            print("✗ " .. test.name .. " FAILED:")
            print("  " .. tostring(err))
        end
    end

    print("\n=== Test Summary ===")
    print(string.format("Passed: %d", passed))
    print(string.format("Failed: %d", failed))
    print(string.format("Total:  %d", passed + failed))

    if failed == 0 then
        print("\n✓ All tests passed!")
    else
        print("\n✗ Some tests failed")
    end

    return failed == 0
end

return M
