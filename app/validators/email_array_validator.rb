# frozen_string_literal: true

class EmailArrayValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    unless value.is_a? Array
      record.errors.add(attribute, "must be an array")
      return
    end

    value.each_with_index do |email, index|
      unless valid? email
        record.errors.add(attribute, "value #{email} at position #{index} is not a valid email address")
      end
    end
  end

  protected

  def valid?(value)
    value&.match(Regex::EMAIL)
  end
end
