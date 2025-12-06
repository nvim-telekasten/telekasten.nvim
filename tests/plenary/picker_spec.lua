-- tests/plenary/picker_spec.lua

describe('Picker Abstraction Layer', function()
  local backends = {'telescope', 'fzf-lua', 'snacks'}
  local picker = require('telekasten.picker')
local utils = require('tests.plenary.test_utils')



  for _, backend_name in ipairs(backends) do
    describe('with ' .. backend_name .. ' backend', function()
      before_each(function()
        picker.setup({ backend = backend_name })
        vim.cmd('silent! %bdelete!') -- Close all buffers
        vim.cmd('silent! enew') -- Start with a new empty buffer
        utils.create_dummy_files({
          'test_note_1.md',
          'test_note_2.md',
          'test_note_3.md',
        })
      end)

      after_each(function()
        utils.cleanup_dummy_files()
      end)

      it('returns the selected path via callback when pick_item is used', function()
        local selected_path = nil
        local dummy_dir = vim.fn.stdpath("cache") .. "/telekasten_test_dummy_notes"
        local items = { dummy_dir .. '/test_note_1.md', dummy_dir .. '/test_note_2.md', dummy_dir .. '/test_note_3.md' }

        picker.pick_item({
          prompt = 'Select a note',
          items = items,
        }, function(selection)
          selected_path = selection
        end)

        if backend_name == 'telescope' or backend_name == 'fzf-lua' then
            vim.api.nvim_feedkeys('jj<C-s>', 'xt', false) -- Select 2nd item and C-s
        elseif backend_name == 'snacks' then
            vim.api.nvim_feedkeys('jj<CR>', 'xt', false) -- Select 2nd item and Enter (snacks default is on_select in pick_item)
        end
        
        assert.is_true(utils.wait_for(1000, function() return selected_path ~= nil end))
        assert.are.equal(items[2], selected_path)
      end)

      it('opens the selected file in a new buffer when find_and_open is used', function()
        local dummy_dir = vim.fn.stdpath("cache") .. "/telekasten_test_dummy_notes"
        local items = { dummy_dir .. '/test_note_1.md', dummy_dir .. '/test_note_2.md', dummy_dir .. '/test_note_3.md' }

        local original_bufnr = vim.api.nvim_get_current_buf()

        picker.find_and_open({
          prompt = 'Open a note',
          items = items,
        })

        vim.api.nvim_feedkeys('j<CR>', 'xt', false) -- Select 1st item and Enter
        
        assert.is_true(utils.wait_for(1000, function() return vim.api.nvim_get_current_buf() ~= original_bufnr and vim.fn.bufname('%'):match('.*/(.*)$') == 'test_note_1.md' end))

        local current_bufname = vim.fn.bufname('%')
        assert.are.equal(items[1], current_bufname)
      end)
    end)
  end
end)