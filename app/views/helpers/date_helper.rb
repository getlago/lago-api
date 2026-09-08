# frozen_string_literal: true

class DateHelper
  def self.format(date, format: :default)
    return if date.nil?

    I18n.l(date, format:)
  end
end
