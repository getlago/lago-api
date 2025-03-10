# frozen_string_literal: true

module Validators
  class MetadataValidator
    DEFAULT_CONFIG = {
      max_keys: 5,
      max_key_length: 20,
      max_value_length: 100
    }.freeze

    attr_reader :metadata, :errors, :config

    def initialize(metadata, config = {})
      @metadata = normalize_metadata(metadata)
      @config = DEFAULT_CONFIG.merge(config)
      @errors = {}
    end

    def valid?
      validate_type && validate_size && @metadata.all? { |item| validate_item(item) }
    end

    private

    def normalize_metadata(metadata)
      return [] if metadata.nil? || metadata == {}
      metadata.is_a?(Array) ? metadata.map { |m| m.to_h.deep_symbolize_keys } : metadata
    end


    def validate_type
      return true if @metadata.is_a?(Array)
      @errors[:metadata] = "invalid_type"
      false
    end

    def validate_size
      return true if @metadata.size <= @config[:max_keys]
      @errors[:metadata] = "too_many_keys"
      false
    end

    def validate_item(item)
      return error!("invalid_key_value_pair") unless valid_key_value_pair?(item)
      return error!("key_too_long") if item[:key].length > @config[:max_key_length]
      return error!("value_too_long") if item[:value].is_a?(String) && item[:value].length > @config[:max_value_length]
      return error!("nested_structure_not_allowed") if item[:value].is_a?(Hash) || item[:value].is_a?(Array)

      true
    end

    def error!(message)
      @errors[:metadata] = message
      false
    end

    def valid_key_value_pair?(item)
      item.is_a?(Hash) && item.keys.sort == [:key, :value] && item[:key] && item[:value]
    end
  end
end