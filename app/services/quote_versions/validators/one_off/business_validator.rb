# frozen_string_literal: true

module QuoteVersions
  module Validators
    module OneOff
      class BusinessValidator < ::BaseValidator
        include Currencies

        def initialize(result, quote_version:, billing_items:, scope:)
          @quote_version = quote_version
          @billing_items = billing_items
          @scope = scope

          super
        end

        def valid?
          validate_currency
          validate_add_ons

          if errors?
            result.validation_failure!(errors:)
            return false
          end

          true
        end

        private

        attr_reader :quote_version, :billing_items, :scope

        def validate_currency
          currency = quote_version.currency

          if currency.blank?
            add_error(field: :currency, error_code: "value_is_mandatory") if scope == :approve
          elsif self.class.currency_list.exclude?(currency)
            add_error(field: :currency, error_code: "invalid_currency")
          end
        end

        def validate_add_ons
          add_ons.each_with_index do |add_on, index|
            validate_add_on_existence(add_on, index)
            validate_datetimes(add_on, index)
          end
        end

        def validate_add_on_existence(add_on, index)
          unless known_add_on_ids.include?(add_on["id"])
            add_error(field: add_on_field(index, "id"), error_code: "add_on_not_found")
          end
        end

        def validate_datetimes(add_on, index)
          %w[payload overrides].each do |section|
            from = add_on.dig(section, "from_datetime")
            to = add_on.dig(section, "to_datetime")
            next if from.nil? && to.nil?

            if from.nil?
              add_error(field: add_on_field(index, "#{section}.from_datetime"), error_code: "value_is_mandatory")
            elsif to.nil?
              add_error(field: add_on_field(index, "#{section}.to_datetime"), error_code: "value_is_mandatory")
            elsif Time.zone.parse(from) > Time.zone.parse(to)
              add_error(field: add_on_field(index, "#{section}.from_datetime"), error_code: "invalid_date_range")
            end
          end
        end

        def add_ons
          billing_items["add_ons"] || []
        end

        def add_on_field(index, suffix)
          :"billing_items.add_ons.#{index}.#{suffix}"
        end

        def known_add_on_ids
          @known_add_on_ids ||= quote_version
            .organization
            .add_ons
            .with_discarded
            .where(id: add_ons.map { |add_on| add_on["id"] })
            .pluck(:id)
            .to_set
        end
      end
    end
  end
end
