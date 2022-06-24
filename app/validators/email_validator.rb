# frozen_string_literal: true

class EmailValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    record.errors.add(attribute, :email_invalids) unless valid?(value)
  end

  protected

  def valid?(value)
    value&.match(URI::MailTo::EMAIL_REGEXP)
  end
end
