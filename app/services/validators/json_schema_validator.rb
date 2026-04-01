# frozen_string_literal: true

module Validators
  class JsonSchemaValidator
    attr_reader :errors

    def initialize(data, schema:)
      @data = data
      @schema = schema
      @errors = []
    end

    def valid?
      @errors = []

      unless @data.is_a?(Hash)
        @errors << {path: "", error: "invalid_type", expected: Hash, actual: @data.class}
        return false
      end

      validate_hash(@data, @schema, path: "")
      @errors.empty?
    end

    private

    def validate_hash(hash, schema, path:)
      unknown_keys = hash.keys - schema.keys
      unknown_keys.each do |key|
        @errors << {path: build_path(path, key), error: "unknown_key"}
      end

      schema.each do |key, rules|
        value = hash[key]
        full_path = build_path(path, key)

        if value.nil?
          @errors << {path: full_path, error: "required"} if rules[:required]
          next
        end

        unless value.is_a?(rules[:type])
          @errors << {path: full_path, error: "invalid_type", expected: rules[:type], actual: value.class}
          next
        end

        if rules[:type] == Hash && rules[:schema]
          validate_hash(value, rules[:schema], path: full_path)
        end

        if rules[:type] == Array && rules[:items]
          validate_array_items(value, rules[:items], path: full_path)
        end
      end
    end

    def validate_array_items(array, item_rules, path:)
      array.each_with_index do |item, index|
        item_path = "#{path}[#{index}]"

        if item_rules[:type] && !item.is_a?(item_rules[:type])
          @errors << {path: item_path, error: "invalid_type", expected: item_rules[:type], actual: item.class}
        elsif item_rules[:schema] && item.is_a?(Hash)
          validate_hash(item, item_rules[:schema], path: item_path)
        end
      end
    end

    def build_path(base, key)
      base.empty? ? key.to_s : "#{base}.#{key}"
    end
  end
end
