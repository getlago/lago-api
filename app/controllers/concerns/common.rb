# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

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
