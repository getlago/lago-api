# frozen_string_literal: true

module Validators
  class MetadataValidator
    DEFAULT_CONFIG = {
      max_keys: 5,
      max_key_length: 20,
      max_value_length: 40
    }.freeze

    attr_reader :metadata, :errors, :config

    def initialize(metadata, config = {})
      @metadata = metadata || []
      @errors = {}
      @config = DEFAULT_CONFIG.merge(config)
    end

    def valid?
      return true if metadata.empty?

      validate_size
      metadata.each { |item| validate_item(item) }

      errors.empty?
    end

    private

    def validate_size
      errors[:metadata] = 'too_many_keys' if metadata.size > config[:max_keys]
    end

    def validate_item(item)
      unless item.is_a?(Hash) && item.keys.sort == %w[key value] && item['key'] && item['value']
        errors[:metadata] = 'invalid_key_value_pair'
        return
      end

      validate_key_length(item['key'])
      validate_value_length(item['value'])
      validate_structure(item['value'])
    end

    def validate_key_length(key)
      errors[:metadata] = 'key_too_long' if key.length > config[:max_key_length]
    end

    def validate_value_length(value)
      errors[:metadata] = 'value_too_long' if value.is_a?(String) && value.length > config[:max_value_length]
    end

    def validate_structure(value)
      errors[:metadata] = 'nested_structure_not_allowed' if value.is_a?(Hash) || value.is_a?(Array)
    end
  end
end
