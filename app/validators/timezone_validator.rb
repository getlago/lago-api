# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

class TimezoneValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    record.errors.add(attribute, :invalid_timezone) unless valid?(value)
  end

  protected

  def valid?(value)
    value == "UTC" || Timezones::MAPPING.value?(value)
  end
end
