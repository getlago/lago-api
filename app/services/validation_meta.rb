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

  # They echo the request, which a validation error never does.
  ECHO_KEYS = %i[value invalid_values].freeze

  EMPTY = {}.freeze

  module_function

  # Symbol keys, without nil values. Bad meta raises in development and test, and is reported and
  # dropped elsewhere, so that the error stays a 4xx.
  def check(meta, echo: true)
    if meta.is_a?(Hash)
      meta.compact.each_with_object({}) do |(key, value), checked|
        name = key.to_sym if key.is_a?(Symbol) || key.is_a?(String)

        if !registered?(name, value)
          report("meta #{key}: #{value.inspect} is not a registered key and type")
        elsif !echo && ECHO_KEYS.include?(name)
          report("meta #{key} echoes the request, which a validation error never does")
        else
          checked[name] = value
        end
      end.freeze
    else
      report("meta is not a Hash: #{meta.class}") unless meta.nil?
      EMPTY
    end
  end

  # {field => [Hash]}, where position i describes code i of messages[field]. A field whose codes
  # carry nothing is left out.
  def align(messages, meta)
    if meta.is_a?(Hash)
      meta.each_with_object({}) do |(field, items), aligned|
        # Only a key that messages iterates with, which entries reads the meta back with.
        codes = messages.fetch(field, nil) if messages.is_a?(Hash) && messages.each_key.include?(field)

        if codes.is_a?(Array) && items.is_a?(Array) && items.size <= codes.size
          checked = items.map { check(it, echo: false) }
          aligned[field] = (checked + Array.new(codes.size - checked.size, EMPTY)).freeze if checked.any?(&:present?)
        else
          report("meta of #{field.inspect} does not match its codes")
        end
      end.freeze
    else
      report("meta is not a Hash of fields: #{meta.class}") unless meta.nil?
      EMPTY
    end
  end

  # The `meta:` option of the record's errors, aligned with record.errors.messages, which groups
  # errors.objects by attribute in the same order.
  def for_record(record)
    record.errors.group_by_attribute.each_with_object({}) do |(attribute, errors), meta|
      items = errors.map { it.options[:meta] || EMPTY }
      meta[attribute] = items if items.any?(&:present?)
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
      # Never raised, so without it the event would not show which producer sent the meta.
      error.set_backtrace(caller)
      Sentry.capture_exception(error)
    end
  end

  private_class_method :registered?, :report
end
