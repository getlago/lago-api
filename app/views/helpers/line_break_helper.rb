# frozen_string_literal: true

class LineBreakHelper
  def self.break_lines(text)
    escaped_text = ERB::Util.html_escape(text.to_s)
    escaped_text.gsub("\n", "<br/>").html_safe # rubocop:disable Rails/OutputSafety
  end
end
