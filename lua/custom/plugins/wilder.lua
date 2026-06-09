return {
  'gelguy/wilder.nvim',
  event = 'CmdlineEnter',
  config = function()
    local wilder = require 'wilder'
    wilder.setup { modes = { ':', '/', '?' } }

    local gradient = {
      '#f4bf75', '#f5a623', '#e8784a', '#d9534f',
    }

    for i, fg in ipairs(gradient) do
      vim.api.nvim_set_hl(0, 'WilderGradient' .. i, { fg = fg, bold = true })
    end

    local highlights = wilder.highlighter_with_gradient {
      wilder.basic_highlighter(),
    }

    wilder.set_option(
      'renderer',
      wilder.popupmenu_renderer {
        highlighter = highlights,
        left = { ' ', wilder.popupmenu_devicons() },
        right = { ' ', wilder.popupmenu_scrollbar() },
        highlights = {
          default = 'Pmenu',
          border = 'Pmenu',
          accent = wilder.make_hl('WilderAccent', 'Pmenu', {
            { a = 1 },
            { a = 1 },
            { foreground = '#e8784a', bold = true },
          }),
        },
      }
    )

    wilder.set_option('pipeline', {
      wilder.branch(
        wilder.cmdline_pipeline { fuzzy = 1 },
        wilder.search_pipeline()
      ),
    })
  end,
}
