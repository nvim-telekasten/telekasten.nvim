-- lua/telekasten/picker/fzf_test.lua
-- Test functions for fzf-lua picker (using taglinks testing pattern)

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
    local fzf = require("telekasten.picker.fzf")

    -- Test required functions exist
    assert(fzf.find_files ~= nil, "find_files missing")
    assert(fzf.live_grep ~= nil, "live_grep missing")
    assert(fzf.custom_picker ~= nil, "custom_picker missing")
    assert(fzf.setup ~= nil, "setup missing")

    -- Test actions exist
    assert(fzf.actions ~= nil, "actions table missing")
    assert(fzf.actions.select_default ~= nil, "select_default action missing")
    assert(fzf.actions.close ~= nil, "close action missing")
    assert(fzf.actions.yank_selection ~= nil, "yank_selection action missing")
    assert(fzf.actions.paste_selection ~= nil, "paste_selection action missing")
    assert(fzf.actions.get_selection ~= nil, "get_selection action missing")
    assert(
        fzf.actions.get_current_line ~= nil,
        "get_current_line action missing"
    )

    -- Test themes exist
    assert(fzf.themes ~= nil, "themes table missing")
    assert(fzf.themes.dropdown ~= nil, "dropdown theme missing")
    assert(fzf.themes.ivy ~= nil, "ivy theme missing")
    assert(fzf.themes.cursor ~= nil, "cursor theme missing")

    print("✓ Backend structure tests passed")
end

-- Test actions functionality
M._test_actions = function()
    local fzf = require("telekasten.picker.fzf")

    -- Test get_selection with no selection
    fzf._current_selection = nil
    local result = fzf.actions.get_selection()
    assert(result == nil, "get_selection should return nil when no selection")

    -- Test get_selection with selection
    fzf._current_selection = "/test/path.md"
    result = fzf.actions.get_selection()
    _expect(result, {
        value = "/test/path.md",
        filename = "/test/path.md",
    }, "get_selection with file")

    -- Test get_current_line
    fzf._current_line = nil
    result = fzf.actions.get_current_line()
    assert(result == "", "get_current_line should return empty string when nil")

    fzf._current_line = "test line"
    result = fzf.actions.get_current_line()
    assert(result == "test line", "get_current_line should return stored line")

    -- Cleanup
    fzf._current_selection = nil
    fzf._current_line = nil

    print("✓ Actions tests passed")
end

-- Test themes configuration
M._test_themes = function()
    local fzf = require("telekasten.picker.fzf")

    -- Test dropdown theme
    local dropdown = fzf.themes.dropdown()
    assert(dropdown.winopts ~= nil, "dropdown should have winopts")
    assert(dropdown.winopts.height == 0.4, "dropdown height should be 0.4")
    assert(dropdown.winopts.width == 0.6, "dropdown width should be 0.6")

    -- Test ivy theme
    local ivy = fzf.themes.ivy()
    assert(ivy.winopts ~= nil, "ivy should have winopts")
    assert(ivy.winopts.height == 0.4, "ivy height should be 0.4")
    assert(ivy.winopts.row == 1.0, "ivy should be at bottom")

    -- Test cursor theme
    local cursor = fzf.themes.cursor()
    assert(cursor.winopts ~= nil, "cursor should have winopts")
    assert(cursor.winopts.height == 0.3, "cursor height should be 0.3")
    assert(cursor.winopts.width == 0.3, "cursor width should be 0.3")

    -- Test theme merging
    local custom_dropdown = fzf.themes.dropdown({
        winopts = { width = 0.8 },
    })
    assert(
        custom_dropdown.winopts.width == 0.8,
        "theme should merge custom width"
    )
    assert(
        custom_dropdown.winopts.height == 0.4,
        "theme should keep default height"
    )

    print("✓ Theme tests passed")
end

-- Test utilities
M._test_utilities = function()
    local fzf = require("telekasten.picker.fzf")

    -- Test supports
    assert(fzf.supports("live_grep") == true, "should support live_grep")
    assert(fzf.supports("themes") == true, "should support themes")
    assert(
        fzf.supports("nonexistent") == false,
        "should not support unknown feature"
    )

    -- Test create_entry_display
    local formatter = fzf.create_entry_display({})
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
    local fzf = require("telekasten.picker.fzf")
    local picker_init = require("telekasten.picker.init")

    local valid, err = picker_init.validate_backend(fzf)
    assert(valid == true, "fzf backend should pass validation: " .. (err or ""))

    print("✓ Validation tests passed")
end

-- Test picker initialization
M._test_picker_init = function()
    local picker_init = require("telekasten.picker.init")

    -- Test setup with fzf
    picker_init.setup("fzf", {})
    assert(picker_init.get_backend() == "fzf", "backend should be set to fzf")

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
    print("\n=== Running FZF Picker Tests ===\n")

    local tests = {
        { name = "Backend Structure", fn = M._test_backend_structure },
        { name = "Actions", fn = M._test_actions },
        { name = "Themes", fn = M._test_themes },
        { name = "Utilities", fn = M._test_utilities },
        { name = "Validation", fn = M._test_validation },
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
