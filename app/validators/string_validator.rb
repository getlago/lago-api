# frozen_string_literal: true

# Refuses a value that is not a String as it was assigned, which the attribute cast would otherwise
# accept (`123` becomes "123", `true` becomes "t"). A Symbol is accepted: a request body never holds
# one. A nil value is left to `presence`.
class StringValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    raw_value = record.respond_to?(:"#{attribute}_before_type_cast") ? record.public_send(:"#{attribute}_before_type_cast") : value

    record.errors.add(attribute, :invalid) unless raw_value.nil? || raw_value.is_a?(String) || raw_value.is_a?(Symbol)
  end
end
