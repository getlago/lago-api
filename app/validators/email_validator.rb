# frozen_string_literal: true

class EmailValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    record.errors.add(attribute, :invalid_email_format) unless valid?(value)
  end

  protected

  def valid?(value)
    return false if value.blank?

    emails = value.split(",").map(&:strip)

    emails.all? { |email| email.match?(Regex::EMAIL) }
  end
end
