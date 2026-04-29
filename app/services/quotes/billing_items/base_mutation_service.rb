# frozen_string_literal: true

module Quotes
  module BillingItems
    class BaseMutationService < BaseService
      Result = BaseResult[:quote_version]

      private

      attr_reader :quote_version

      def current_items(type)
        billing_items = (quote_version.billing_items || {}).transform_keys(&:to_s)
        billing_items.fetch(type.to_s, []).map { |item| item.transform_keys(&:to_s) }
      end

      def persist_items(type, items)
        existing = (quote_version.billing_items || {}).transform_keys(&:to_s)
        quote_version.update!(billing_items: existing.merge(type.to_s => items))
        result.quote_version = quote_version.reload
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end
    end
  end
end
