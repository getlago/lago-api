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

  # They echo the request, which only a 400 may do.
  ECHO_KEYS = %i[value invalid_values].freeze

  module_function

  # Symbol keys, without nil values, and Symbols rendered as the Strings their JSON is. A key that is
  # not registered with its type, or that echoes the request outside a 400, raises in development and
  # test. Elsewhere it is reported and the whole meta is dropped, so that the error stays a 4xx and a
  # client never reads half of it, such as a min without its max.
  def check(meta, echo: false)
    if meta.is_a?(Hash)
      # symbolize_keys leaves a key that has no Symbol form, such as an Integer, as it is.
      checked = meta.compact.symbolize_keys.transform_values { stringify_symbols(it) }
      refusals = checked.filter_map { |key, value| refusal(key, value, echo) }

      if refusals.empty?
        checked
      else
        refusals.each { report(it) }
        {}
      end
    else
      report("meta is not a Hash: #{meta.class}") unless meta.nil?
      {}
    end
  end

  def refusal(key, value, echo)
    if !registered?(key, value)
      "meta #{key}: #{value.inspect} is not a registered key and type"
    elsif !echo && ECHO_KEYS.include?(key)
      "meta #{key} echoes the request, which only a 400 may do"
    end
  end

  def stringify_symbols(value)
    case value
    when Symbol then value.to_s
    when Array then value.map { it.is_a?(Symbol) ? it.to_s : it }
    else value
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

  private_class_method :refusal, :stringify_symbols, :registered?
end
