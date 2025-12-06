-- tests/plenary/test_utils.lua

local M = {}

local DUMMY_DIR = vim.fn.stdpath("cache") .. "/telekasten_test_dummy_notes"

function M.create_dummy_files(filenames)
    vim.fn.mkdir(DUMMY_DIR, "p")
    for _, filename in ipairs(filenames) do
        local full_path = DUMMY_DIR .. "/" .. filename
        vim.fn.writefile({ "content for " .. filename }, full_path)
    end
    return DUMMY_DIR
end

function M.cleanup_dummy_files()
    if vim.fn.isdirectory(DUMMY_DIR) == 1 then
        vim.fn.delete(DUMMY_DIR, "rf")
    end
end

-- A more robust wait function for async operations
-- It waits until a condition is met or a timeout occurs.
function M.wait_for(timeout_ms, condition_fn, interval_ms)
    interval_ms = interval_ms or 10
    local start_time = vim.loop.hrtime()
    while (vim.loop.hrtime() - start_time) / 1000000 < timeout_ms do
        if condition_fn() then
            return true
        end
        vim.thread_wait(interval_ms)
    end
    return false
end

return M
