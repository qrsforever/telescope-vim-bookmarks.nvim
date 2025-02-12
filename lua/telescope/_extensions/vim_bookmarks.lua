local Path = require "plenary.path"
local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local entry_display = require('telescope.pickers.entry_display')
local conf = require('telescope.config').values
local make_entry = require('telescope.make_entry')

local utils = require('telescope.utils')

local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local bookmark_actions = require('telescope._extensions.vim_bookmarks.actions')

local function get_bookmarks(files, opts)
    opts = opts or {}
    local bookmarks = {}

    for _,file in ipairs(files) do
        for _,line in ipairs(vim.fn['bm#all_lines'](file)) do
            local bookmark = vim.fn['bm#get_bookmark_by_line'](file, line)

            local text = bookmark.content
            if text == "" then
                text = "(empty line)"
            end

            local only_annotated = opts.only_annotated or false

            if not (only_annotated and bookmark.annotation == "") then
                table.insert(bookmarks, {
                    filename = file,
                    lnum = tonumber(line),
                    col=1,
                    text = text,
                    annotation = bookmark.annotation,
                    sign_idx = bookmark.sign_idx,
                })
            end
        end
    end

    return bookmarks
end

local function make_entry_from_bookmarks(opts)
    opts = opts or {}
    opts.tail_path = vim.F.if_nil(opts.tail_path, true)

    local displayer = entry_display.create {
        separator = "▏",
        items = {
            { width = opts.width_line or  5 },
            { width = opts.width_name or 20 },
            { width = opts.width_anno or 20 },
            { width = opts.width_path or 70 },
            { remaining = true }
        }
    }

    local make_display = function(entry)
        local line_info = {entry.lnum, "TelescopeResultsLineNr"}
        local annotation = entry.anno
        local entry_path = entry.filename
        if annotation == ""
        then
            local gitdir = vim.fn.finddir(".git", entry.filename .. ";")
            if gitdir ~= "" then
                local gitroot = Path:new(gitdir):parent():absolute()
                annotation = string.gsub(gitroot, "(.*/)(.*)", "%2")
                entry_path = string.sub(entry_path, string.len(gitroot) + 2, string.len(entry_path))
            end
            entry_path = entry.text
        end

        return displayer {
            line_info,
            utils.path_tail(entry.filename),
            annotation,
            entry_path,
        }
    end

    return function(entry)
        return {
            valid = true,
            value = entry,
            ordinal = (
            not opts.ignore_filename and entry.filename
            or ''
            ) .. ' ' .. entry.text,
            display = make_display,
            filename = entry.filename,
            lnum = entry.lnum,
            anno = entry.annotation,
            text = entry.text,
            col = 1,
        }
    end
end

local function make_bookmark_picker(filenames, opts)
    opts = opts or {}

    local make_finder = function()
        local bookmarks = get_bookmarks(filenames, opts)

        if vim.tbl_isempty(bookmarks) then
            print("No bookmarks!")
            return
        end

        return finders.new_table {
            results = bookmarks,
            entry_maker = make_entry_from_bookmarks(opts),
        }
    end

    local initial_finder = make_finder()
    if not initial_finder then return end

    pickers.new(opts, {
        prompt_title = opts.prompt_title or "vim-bookmarks",
        finder = initial_finder,
        previewer = conf.qflist_previewer(opts),
        sorter = conf.generic_sorter(opts),

        attach_mappings = function(prompt_bufnr, map)
            local refresh_picker = function()
                local new_finder = make_finder()
                if new_finder then
                    action_state.get_current_picker(prompt_bufnr):refresh(make_finder())
                else
                    actions.close(prompt_bufnr)
                end
            end

            bookmark_actions.delete_selected:enhance { post = refresh_picker }
            bookmark_actions.delete_at_cursor:enhance { post = refresh_picker }
            bookmark_actions.delete_all:enhance { post = refresh_picker }
            bookmark_actions.delete_selected_or_at_cursor:enhance { post = refresh_picker }

            return true
        end
    }):find()
end

local all = function(opts)
    make_bookmark_picker(vim.fn['bm#all_files'](), opts)
end

local current_file = function(opts)
    opts = opts or {}
    opts = vim.tbl_extend('keep', opts, {path_display = true})

    make_bookmark_picker({vim.fn.expand('%:p')}, opts)
end

return require('telescope').register_extension {
    exports = {
        -- Default when to argument is given, i.e. :Telescope vim_bookmarks
        vim_bookmarks = all,

        all = all,
        current_file = current_file,
        actions = bookmark_actions
    }
}
