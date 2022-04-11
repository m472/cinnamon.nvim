local fn = {}

local config = require('cinnamon.config')
local utils = require('cinnamon.utils')
local motions = require('cinnamon.motions')

local check_for_fold = function(counter)
  local fold_start = vim.fn.foldclosed('.')

  -- If a fold exists, add the length to the counter.
  if fold_start ~= -1 then
    local fold_size = vim.fn.foldclosedend(fold_start) - fold_start
    counter = counter + fold_size
  end
  return counter
end

local create_delay = function(remaining, delay, slowdown)
  vim.cmd('redraw')

  -- Don't create a delay when scrolling comleted.
  if remaining <= 0 then
    return
  end

  -- Increase the delay near the end of the scroll.
  if remaining <= 4 and slowdown == 1 then
    vim.cmd('sleep ' .. delay * (5 - remaining) .. 'm')
  else
    vim.cmd('sleep ' .. delay .. 'm')
  end
end

local scroll_screen = function(remaining, delay, slowdown, target_line)
  target_line = target_line or math.ceil(vim.api.nvim_win_get_height(0) / 2)

  local prev_line = vim.fn.winline()

  -- Scroll up the screen.
  while vim.fn.winline() > target_line do
    vim.cmd('silent exe "norm! \\<C-E>"')
    local new_line = vim.fn.winline()
    create_delay(new_line - target_line + remaining, delay, slowdown)
    if new_line == prev_line then
      break
    end
    prev_line = new_line
  end

  -- Scroll down the screen.
  while vim.fn.winline() < target_line do
    vim.cmd('silent exe "norm! \\<C-Y>"')
    local new_line = vim.fn.winline()
    create_delay(target_line - new_line + remaining, delay, slowdown)
    if new_line == prev_line then
      break
    end
    prev_line = new_line
  end
end

fn.check_command_errors = function(command)
  -- If no search pattern, return an error if using a repeat search command.
  if utils.contains(motions.search_repeat, command) then
    local pattern = vim.fn.getreg('/')
    if pattern == '' then
      utils.error_msg('The search pattern is empty')
      return true
    end
    if vim.fn.search(pattern, 'nw') == 0 then
      utils.error_msg('Pattern not found: ' .. vim.fn.getreg('/'), 'E486')
      return true
    end
  end

  -- If no word under cursor, return an error if using a word-near-cursor search command.
  if utils.contains(motions.search_cursor, command) then
    -- Check if string is empty or only whitespace.
    if vim.fn.getline('.'):match('^%s*$') then
      utils.error_msg('No string under cursor', 'E348')
      return true
    end
  end

  -- If no word under cursor, return an error if using a goto declaration command.
  if utils.contains(motions.goto_declaration, command) then
    -- Check if string is empty or only whitespace.
    if vim.fn.getline('.'):match('^%s*$') then
      utils.error_msg('No identifier under cursor', 'E349')
      return true
    end
  end

  -- If no errors, return false.
  return false
end

fn.scroll_down = function(distance, command, scroll_win, delay, slowdown)
  local win_height = vim.api.nvim_win_get_height(0)

  -- Disable slowdown for window scrolling movements.
  if utils.contains(motions.window_scroll, command) then
    slowdown = 0
  end

  -- Center the screen.
  local half_height = math.ceil(win_height / 2)
  if vim.fn.winline() > half_height and scroll_win == 1 and config.centered then
    scroll_screen(distance, delay, slowdown)
  end

  -- Scroll.
  local counter = 1
  while counter <= distance do
    counter = check_for_fold(counter)
    vim.cmd('norm! j')
    if scroll_win == 1 then
      local screen_line = vim.fn.winline()
      if config.centered then
        if screen_line > half_height then
          vim.cmd('silent exe "norm! \\<C-E>"')
        end
      else
        -- Scroll the window if the current line is not contains 'scrolloff'.
        local scrolloff = vim.opt.so:get()
        if not (screen_line <= scrolloff + 1 or screen_line >= win_height - scrolloff) then
          vim.cmd('silent exe "norm! \\<C-E>"')
        end
      end
    end
    counter = counter + 1
    create_delay(distance - counter, delay, slowdown)
  end

  -- Center the screen.
  if scroll_win == 1 and config.centered then
    scroll_screen(0, delay, slowdown)
  end
end

fn.scroll_up = function(distance, command, scroll_win, delay, slowdown)
  local win_height = vim.api.nvim_win_get_height(0)

  -- Disable slowdown for window scrolling movements.
  if utils.contains(motions.window_scroll, command) then
    slowdown = 0
  end

  -- Center the screen.
  local half_height = math.ceil(win_height / 2)
  if vim.fn.winline() < half_height and scroll_win == 1 and config.centered then
    scroll_screen(-distance, delay, slowdown)
  end

  -- Scroll.
  local counter = 1
  while counter <= -distance do
    counter = check_for_fold(counter)
    vim.cmd('norm! k')
    if scroll_win == 1 then
      local screen_line = vim.fn.winline()
      if config.centered then
        if screen_line < half_height then
          vim.cmd('silent exe "norm! \\<C-Y>"')
        end
      else
        -- Scroll the window if the current line is not contains 'scrolloff'.
        local scrolloff = vim.opt.so:get()
        if not (screen_line <= scrolloff + 1 or screen_line >= win_height - scrolloff) then
          vim.cmd('silent exe "norm! \\<C-Y>"')
        end
      end
    end
    counter = counter + 1
    create_delay(-distance + counter, delay, slowdown)
  end

  -- Center the screen.
  if scroll_win == 1 and config.centered then
    scroll_screen(0, delay, slowdown)
  end
end

fn.window_scroll = function(command, delay, slowdown)
  local window_height = vim.api.nvim_win_get_height(0)
  local half_height = math.ceil(window_height / 2)
  local scrolloff = vim.opt.so:get()

  if scrolloff >= half_height then
    scroll_screen(0, delay, slowdown)
    return
  end

  if utils.contains(motions.window_scroll_top, command) then
    scroll_screen(0, delay, slowdown, scrolloff + 1)
  elseif utils.contains(motions.window_scroll_bottom, command) then
    scroll_screen(0, delay, slowdown, window_height - scrolloff)
  else
    scroll_screen(0, delay, slowdown)
  end
end

fn.get_scroll_distance = function(command, use_count, scroll_win)
  local saved_view = vim.fn.winsaveview()

  local _, prev_row, _, _, prev_curswant = unpack(vim.fn.getcurpos())
  local prevFile = vim.fn.getreg('%')

  -- Perform the command.
  if command == 'definition' then
    require('vim.lsp.buf').definition()
    vim.cmd('sleep 100m')
  elseif command == 'declaration' then
    require('vim.lsp.buf').declaration()
    vim.cmd('sleep 100m')
  elseif use_count ~= 0 and vim.v.count > 0 then
    vim.cmd('norm! ' .. vim.v.count .. command)
  else
    vim.cmd('norm! ' .. command)
  end

  -- If searching contains a fold, open the fold.
  if utils.contains(motions.search, command) and vim.fn.foldclosed('.') ~= -1 then
    vim.cmd('norm! zo')
  end

  local _, new_row, new_column, _, new_curswant = unpack(vim.fn.getcurpos())

  -- Check if the file has changed.
  if prevFile ~= vim.fn.getreg('%') then
    vim.cmd('norm! zz')
    return 0, -1, true, false
  end

  local distance = new_row - prev_row

  -- Check if scroll limit has been exceeded.
  if distance > config.scroll_limit or distance < -config.scroll_limit then
    if scroll_win == 1 and config.centered then
      vim.cmd('norm! zz')
    end
    return 0, -1, false, true
  end

  -- Check if curswant has changed.
  if prev_curswant == new_curswant then
    new_column = -1
  end

  -- Restore the view to before the command was executed.
  vim.fn.winrestview(saved_view)
  return distance, new_column, false, false
end

return fn
