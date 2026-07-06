# frozen_string_literal: true

module QuoteVersions
  module Validators
    module OneOff
      class BusinessService
        attr_reader :errors

        def initialize(quote_version:, billing_items:, scope:, payload_valid:)
          @quote_version = quote_version
          @billing_items = billing_items || {}
          @scope = scope
          @payload_valid = payload_valid
          @errors = {}
        end

        def valid?
          validate_currency
          validate_customer if scope == :approve
          validate_addons if payload_valid

          errors.empty?
        end

        private

        attr_reader :quote_version, :billing_items, :scope, :payload_valid

        def validate_currency
          currency = quote_version.currency

          if currency.blank?
            add_error(field: :currency, code: "value_is_mandatory") if scope == :approve
          elsif !Currencies::ACCEPTED_CURRENCIES.key?(currency.to_sym)
            add_error(field: :currency, code: "invalid_currency")
          end
        end

        def validate_customer
          unless Customer.exists?(id: quote_version.quote.customer_id)
            add_error(field: :customer, code: "customer_not_found")
          end
        end

        def validate_addons
          addons.each_with_index do |addon, index|
            validate_add_on_existence(addon, index)
            validate_datetimes(addon, index)
          end
        end

        def validate_add_on_existence(addon, index)
          unless known_add_on_ids.include?(addon["id"])
            add_error(field: addon_field(index, "id"), code: "add_on_not_found")
          end
        end

        def validate_datetimes(addon, index)
          from = addon.dig("payload", "from_datetime")
          to = addon.dig("payload", "to_datetime")
          return if from.nil? && to.nil?

          if from.nil?
            add_error(field: addon_field(index, "payload.from_datetime"), code: "value_is_mandatory")
          elsif to.nil?
            add_error(field: addon_field(index, "payload.to_datetime"), code: "value_is_mandatory")
          elsif Time.zone.parse(from) > Time.zone.parse(to)
            add_error(field: addon_field(index, "payload.from_datetime"), code: "invalid_date_range")
          end
        end

        def addons
          billing_items["addons"] || []
        end

        def addon_field(index, suffix)
          :"billing_items.addons.#{index}.#{suffix}"
        end

        def known_add_on_ids
          @known_add_on_ids ||= quote_version
            .organization
            .add_ons
            .with_discarded
            .where(id: addons.map { |addon| addon["id"] })
            .pluck(:id)
            .to_set
        end

        def add_error(field:, code:)
          errors[field.to_sym] ||= []
          errors[field.to_sym] << code
        end
      end
    end
  end
end
