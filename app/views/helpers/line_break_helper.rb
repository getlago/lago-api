# frozen_string_literal: true

class LineBreakHelper
  def self.break_lines(text)
    escaped_text = ERB::Util.html_escape(text)
    escaped_text.to_s.gsub(/\n/, '<br/>').html_safe # rubocop:disable Rails/OutputSafety
  end
end
