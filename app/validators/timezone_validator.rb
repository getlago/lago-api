# frozen_string_literal: true

class TimezoneValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    record.errors.add(attribute, :timzone_invalid) unless valid?(value)
  end

  protected

  def valid?(value)
    value && ActiveSupport::TimeZone[value].present?
  end
end
