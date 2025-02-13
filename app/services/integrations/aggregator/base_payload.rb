# frozen_string_literal: true

module Integrations
  module Aggregator
    class BasePayload
      class Failure < BaseService::FailedResult
        attr_reader :code

        def initialize(result, code:)
          @code = code

          super(result, code)
        end
      end

      def initialize(integration:)
        @integration = integration
      end

      def billable_metric_item(fee)
        integration
          .integration_mappings
          .find_by(mappable_type: "BillableMetric", mappable_id: fee.billable_metric.id) || fallback_item
      end

      def add_on_item(fee)
        integration
          .integration_mappings
          .find_by(mappable_type: "AddOn", mappable_id: fee.add_on_id) || fallback_item
      end

      def account_item
        @account_item ||= collection_mapping(:account) || fallback_item
      end

      def tax_item
        @tax_item ||= collection_mapping(:tax)
      end

      def commitment_item
        @commitment_item ||= collection_mapping(:minimum_commitment) || fallback_item
      end

      def subscription_item
        @subscription_item ||= collection_mapping(:subscription_fee) || fallback_item
      end

      def coupon_item
        @coupon_item ||= collection_mapping(:coupon) || fallback_item
      end

      def credit_item
        @credit_item ||= collection_mapping(:prepaid_credit) || fallback_item
      end

      def credit_note_item
        @credit_note_item ||= collection_mapping(:credit_note) || fallback_item
      end

      def fallback_item
        @fallback_item ||= collection_mapping(:fallback_item)
      end

      def amount(amount_cents, resource:)
        currency = resource.total_amount.currency

        amount_cents.round.fdiv(currency.subunit_to_unit)
      end

      def collection_mapping(type)
        integration.integration_collection_mappings.where(mapping_type: type)&.first
      end

      private

      attr_reader :integration

      def tax_item_complete?
        tax_item&.tax_nexus.present? && tax_item&.tax_type.present? && tax_item&.tax_code.present?
      end

      def formatted_date(date)
        date&.strftime("%Y-%m-%d")
      end
    end
  end
end
