# frozen_string_literal: true

# Facts in a v2 error entry that let a client fix its next request, or tell which provider failed.
# Each key keeps one meaning and one JSON type across codes, so it is declared here once.
module ValidationMeta
  # A bound that is exclusive, or that is not an Integer, gets keys of its own when a producer first
  # needs one, so that these keep their meaning and their type.
  KEYS = {
    min: Integer, # inclusive bound on the value, in the unit of the field
    max: Integer,
    min_length: Integer, # inclusive bound on the length of a String, in characters
    max_length: Integer,
    max_items: Integer, # inclusive bound on the number of elements, of a list or behind an expansion
    allowed_values: [String], # every value of the field that the check accepts
    value: String, # the query value received, in a 400 only
    invalid_values: [String], # the refused values received, in a 400 only
    resource: String, # the resource of a resource_not_found, such as customer
    provider_name: String, # the lowercase token of the provider that failed or throttled, such as stripe
    provider_code: String, # the code of the connection of the organization to that provider
    provider_error_code: String # the provider's own error token, such as resource_missing or card_declined
  }.freeze

  module_function

  # The meta as its JSON reads, Symbols as Strings, with Symbol keys and without nil values. A key that
  # is not registered with its type raises in development and test. Elsewhere it is reported and the
  # whole meta is dropped, so that a client never reads half of it, such as a min without its max.
  def check(meta)
    checked = (meta || {}).compact.as_json.symbolize_keys
    refused = checked.reject { |key, value| registered?(key, value) }

    if refused.empty?
      checked
    else
      refused.each { |key, value| report("meta #{key}: #{value.inspect} is not a registered key and type") }
      {}
    end
  end

  def registered?(key, value)
    type = KEYS[key]

    case type
    when Array then value.is_a?(Array) && value.all?(type.first)
    when Class then value.is_a?(type)
    else false
    end
  end

  # Logged too, so that an install without Sentry keeps a trace.
  def report(message)
    error = ArgumentError.new(message)

    if Rails.env.local?
      raise error
    else
      Rails.logger.warn("ValidationMeta: #{message}")
      Sentry.capture_exception(error) if defined?(Sentry)
    end
  end

  private_class_method :registered?
end
