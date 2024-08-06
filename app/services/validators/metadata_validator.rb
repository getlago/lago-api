# frozen_string_literal: true

module Validators
  class MetadataValidator
    DEFAULT_CONFIG = {
      max_keys: 10,
      max_key_length: 20,
      max_value_length: 100
    }.freeze

    attr_reader :metadata, :errors, :config

    def initialize(metadata, config = {})
      @metadata = metadata
      @errors = {}
      @config = DEFAULT_CONFIG.merge(config)
    end

    def valid?
      return true if metadata.blank?

      validate_size
      validate_keys_and_values
      validate_structure

      errors.empty?
    end

    private

    def validate_size
      if metadata.size > config[:max_keys]
        errors[:metadata] = 'too_many_keys'
      end
    end

    def validate_keys_and_values
      metadata.each do |key, value|
        if key.length > config[:max_key_length]
          errors[:metadata] = 'key_too_long'
        end
        if value.is_a?(String) && value.length > config[:max_value_length]
          errors[:metadata] = 'value_too_long'
        end
      end
    end

    def validate_structure
      metadata.each do |_, value|
        if value.is_a?(Hash) || value.is_a?(Array)
          errors[:metadata] = 'nested_structure_not_allowed'
        end
      end
    end
  end
end
