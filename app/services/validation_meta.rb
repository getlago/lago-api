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
    third_party: String, # the provider of a third_party_error
    provider_code: String, # the code of the payment provider of a provider_error
    provider_name: String # the provider of a too_many_provider_requests error
  }.freeze

  # They echo the request, which only a 400 may do.
  ECHO_KEYS = %i[value invalid_values].freeze

  module_function

  # Symbol keys, without nil values. A key that is not registered with its type, or that echoes the
  # request outside a 400, raises in development and test, and is dropped and reported elsewhere, so
  # that the error stays a 4xx.
  def check(meta, echo: false)
    if meta.is_a?(Hash)
      meta.compact.each_with_object({}) do |(key, value), checked|
        name = key.to_sym if key.is_a?(Symbol) || key.is_a?(String)

        if !registered?(name, value)
          report("meta #{key}: #{value.inspect} is not a registered key and type")
        elsif !echo && ECHO_KEYS.include?(name)
          report("meta #{key} echoes the request, which only a 400 may do")
        else
          checked[name] = value
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
