# frozen_string_literal: true

module Common
  extend ActiveSupport::Concern

  private

  def valid_date?(date)
    return false unless date

    Date.iso8601(date)
    true
  rescue Date::Error
    false
  end
end
