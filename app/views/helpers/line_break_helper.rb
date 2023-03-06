# frozen_string_literal: true

class LineBreakHelper
  def self.break_lines(text)
    text.to_s.gsub(/\n/, '<br/>').sanitize.html_safe
  end
end
