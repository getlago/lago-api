# frozen_string_literal: true

require 'rack/utils'

class LineBreakHelper
  def self.break_lines(text)
    escaped_text = Rack::Utils.escape_html(text)
    escaped_text.to_s.gsub(/\n/, '<br/>').html_safe
  end
end
