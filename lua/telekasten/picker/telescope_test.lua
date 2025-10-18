-- lua/telekasten/picker/telescope_test.lua
-- Test functions for telescope picker (using taglinks testing pattern)

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
    local telescope = require("telekasten.picker.telescope")

    -- Test required functions exist
    assert(telescope.find_files ~= nil, "find_files missing")
    assert(telescope.live_grep ~= nil, "live_grep missing")
    assert(telescope.custom_picker ~= nil, "custom_picker missing")
    assert(telescope.setup ~= nil, "setup missing")

    -- Test actions exist
    assert(telescope.actions ~= nil, "actions table missing")
    assert(
        telescope.actions.select_default ~= nil,
        "select_default action missing"
    )
    assert(telescope.actions.close ~= nil, "close action missing")
    assert(
        telescope.actions.yank_selection ~= nil,
        "yank_selection action missing"
    )
    assert(
        telescope.actions.paste_selection ~= nil,
        "paste_selection action missing"
    )
    assert(
        telescope.actions.get_selection ~= nil,
        "get_selection action missing"
    )
    assert(
        telescope.actions.get_current_line ~= nil,
        "get_current_line action missing"
    )

    -- Test themes exist
    assert(telescope.themes ~= nil, "themes table missing")
    assert(telescope.themes.dropdown ~= nil, "dropdown theme missing")
    assert(telescope.themes.ivy ~= nil, "ivy theme missing")
    assert(telescope.themes.cursor ~= nil, "cursor theme missing")

    print("✓ Backend structure tests passed")
end

-- Test actions functionality
M._test_actions = function()
    local telescope = require("telekasten.picker.telescope")

    -- Telescope actions are wrappers around telescope's action_state
    -- We can verify they exist and are functions
    assert(
        type(telescope.actions.select_default) == "function",
        "select_default should be a function"
    )
    assert(
        type(telescope.actions.close) == "function",
        "close should be a function"
    )
    assert(
        type(telescope.actions.yank_selection) == "function",
        "yank_selection should be a function"
    )
    assert(
        type(telescope.actions.paste_selection) == "function",
        "paste_selection should be a function"
    )

    -- Note: get_selection and get_current_line delegate to telescope's action_state
    -- which requires a picker context, so we can't fully test them without a picker
    assert(
        type(telescope.actions.get_selection) == "function",
        "get_selection should be a function"
    )
    assert(
        type(telescope.actions.get_current_line) == "function",
        "get_current_line should be a function"
    )

    print("✓ Actions tests passed")
end

-- Test themes configuration
M._test_themes = function()
    local telescope = require("telekasten.picker.telescope")

    -- Test that theme functions exist and return tables
    local dropdown = telescope.themes.dropdown()
    assert(type(dropdown) == "table", "dropdown should return a table")

    local ivy = telescope.themes.ivy()
    assert(type(ivy) == "table", "ivy should return a table")

    local cursor = telescope.themes.cursor()
    assert(type(cursor) == "table", "cursor should return a table")

    -- Test theme merging
    local custom_dropdown = telescope.themes.dropdown({
        custom_option = true,
    })
    assert(
        type(custom_dropdown) == "table",
        "custom dropdown should return a table"
    )

    print("✓ Theme tests passed")
end

-- Test utilities
M._test_utilities = function()
    local telescope = require("telekasten.picker.telescope")

    -- Test supports - telescope has the most features
    assert(telescope.supports("live_grep") == true, "should support live_grep")
    assert(telescope.supports("themes") == true, "should support themes")
    assert(
        telescope.supports("media_preview") == true,
        "should support media_preview"
    )
    assert(
        telescope.supports("custom_entry_display") == true,
        "should support custom_entry_display"
    )
    assert(telescope.supports("devicons") == true, "should support devicons")
    assert(
        telescope.supports("nonexistent") == false,
        "should not support unknown feature"
    )

    -- Test create_entry_display
    local formatter = telescope.create_entry_display({
        separator = " ",
        items = {
            { width = 10 },
            { remaining = true },
        },
    })
    assert(
        type(formatter) == "function",
        "create_entry_display should return function"
    )

    print("✓ Utility tests passed")
end

-- Test backend validation
M._test_validation = function()
    local telescope = require("telekasten.picker.telescope")
    local picker_init = require("telekasten.picker.init")

    local valid, err = picker_init.validate_backend(telescope)
    assert(
        valid == true,
        "telescope backend should pass validation: " .. (err or "")
    )

    print("✓ Validation tests passed")
end

-- Test picker initialization
M._test_picker_init = function()
    local picker_init = require("telekasten.picker.init")

    -- Test setup with telescope
    picker_init.setup("telescope", {})
    assert(
        picker_init.get_backend() == "telescope",
        "backend should be set to telescope"
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
    print("\n=== Running Telescope Picker Tests ===\n")

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
