# frozen_string_literal: true

class EmailValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    record.errors.add(attribute, :invalid_email_format) unless valid?(value)
  end

  protected

  def valid?(value)
    value&.match(URI::MailTo::EMAIL_REGEXP)
  end
end
