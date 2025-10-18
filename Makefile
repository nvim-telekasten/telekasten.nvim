.PHONY: test test-taglinks test-telescope test-fzf test-snacks test-all test-watch help

help:
	@echo "Available targets:"
	@echo "  test          - Run all tests (taglinks pattern)"
	@echo "  test-taglinks - Run taglinks tests only"
	@echo "  test-telescope - Run telescope picker tests only"
	@echo "  test-fzf      - Run fzf picker tests only"
	@echo "  test-snacks   - Run snacks picker tests only"
	@echo "  test-all      - Run all tests with color output"
	@echo "  test-watch    - Run tests in watch mode (requires entr)"

test: test-all

test-taglinks:
	@nvim --headless -u NONE -c "set rtp+=." -c "lua require('telekasten.utils.taglinks')._testme()" -c "quit"

test-telescope:
	@nvim --headless -u NONE -c "set rtp+=." -c "lua require('telekasten.picker.telescope_test')._testme()" -c "quit"

test-fzf:
	@nvim --headless -u NONE -c "set rtp+=." -c "lua require('telekasten.picker.fzf_test')._testme()" -c "quit"

test-snacks:
	@nvim --headless -u NONE -c "set rtp+=." -c "lua require('telekasten.picker.snacks_test')._testme()" -c "quit"

test-all:
	@nvim --headless -u NONE -c "set rtp+=." -c "luafile test_all.lua"

test-watch:
	@echo "Watching for changes... (Ctrl+C to stop)"
	@find lua -name "*.lua" | entr -c make test
