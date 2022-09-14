# frozen_string_literal: true

class BaseValidator
  def initialize(result, **args)
    @result = result
    @args = args

    @errors = {}
  end

  protected

  attr_reader :result, :args, :errors

  def add_error(field:, error_code:)
    errors[field.to_sym] ||= []
    errors[field.to_sym] << error_code

    false
  end

  def errors?
    errors.present?
  end
end
