# frozen_string_literal: true

# Facts in a v2 error entry that let a client fix its next request, or tell which provider failed.
# Each key keeps one meaning and one JSON type across codes, so it is declared here once.
module ValidationMeta
  KEYS = {
    min: Integer, # inclusive bound on the value, in the unit of the field
    max: Integer,
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

  # Symbol keys, without nil values. A key that is not registered with its type, or that echoes the
  # request outside a 400, raises in development and test, and is dropped and reported elsewhere, so
  # that the error stays a 4xx.
  def check(meta, echo: false)
    if meta.is_a?(Hash)
      # symbolize_keys leaves a key that has no Symbol form, such as an Integer, as it is.
      meta.compact.symbolize_keys.each_with_object({}) do |(key, value), checked|
        if !registered?(key, value)
          report("meta #{key}: #{value.inspect} is not a registered key and type")
        elsif !echo && ECHO_KEYS.include?(key)
          report("meta #{key} echoes the request, which only a 400 may do")
        else
          checked[key] = value
        end
      end
    else
      report("meta is not a Hash: #{meta.class}") unless meta.nil?
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

  def report(message)
    error = ArgumentError.new(message)

    if Rails.env.local?
      raise error
    elsif defined?(Sentry)
      Sentry.capture_exception(error)
    end
  end

  private_class_method :registered?, :report
end
