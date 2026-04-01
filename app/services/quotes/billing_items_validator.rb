# frozen_string_literal: true

module Quotes
  class BillingItemsValidator < BaseValidator
    def valid?
      validate_schema
      validate_no_duplicates
      validate_positions
      validate_add_on_entries

      if errors?
        result.validation_failure!(errors:)
        return false
      end

      true
    end

    private

    def invalid_format?
      !billing_items.is_a?(Hash)
    end

    def billing_items
      args[:billing_items]
    end

    def order_type
      args[:order_type].to_sym
    end

    def validate_schema
      if invalid_format?
        add_error(field: :billing_items, error_code: "invalid_format")
        return
      end

      schema = BillingItemsSchema::SCHEMAS_BY_ORDER_TYPE[order_type]
      schema_validator = Validators::JsonSchemaValidator.new(billing_items, schema:)

      return if schema_validator.valid?

      schema_validator.errors.each do |err|
        add_error(field: :billing_items, error_code: "invalid_schema_at_#{err[:path]}")
      end
    end

    def validate_no_duplicates
      return if invalid_format?

      check_duplicates(billing_items["coupons"], "coupon_id", "duplicate_coupon")
      check_duplicates(billing_items["add_ons"], "add_on_id", "duplicate_add_on")
    end

    def check_duplicates(items, id_field, error_code)
      return unless items.is_a?(Array)

      ids = items.filter_map { |item| item[id_field] }
      if ids.length != ids.uniq.length
        add_error(field: :billing_items, error_code:)
      end
    end

    def validate_positions
      return if invalid_format?

      check_position_uniqueness(billing_items["coupons"], "coupons")
      check_position_uniqueness(billing_items["wallet_credits"], "wallet_credits")
      check_position_uniqueness(billing_items["add_ons"], "add_ons")
    end

    def check_position_uniqueness(items, array_name)
      return unless items.is_a?(Array)

      positions = items.map { |item| item["position"] }.compact
      if positions.length != positions.uniq.length
        add_error(field: :billing_items, error_code: "duplicate_position_in_#{array_name}")
      end
    end

    def validate_add_on_entries
      return if invalid_format?

      add_ons = billing_items["add_ons"]
      return unless add_ons.is_a?(Array)

      add_ons.each do |add_on|
        if add_on["name"].blank?
          add_error(field: :billing_items, error_code: "add_on_missing_name")
        end

        if add_on["add_on_id"].blank? && add_on["add_on_code"].blank? && add_on["amount_cents"].blank?
          add_error(field: :billing_items, error_code: "custom_add_on_missing_amount")
        end
      end
    end
  end
end
