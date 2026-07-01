# frozen_string_literal: true

module QuoteVersions
  module Snapshots
    # Freezes each add-on's catalog data into billing_items at approval so later
    # catalog edits or soft-deletes never change the deal. Runs after validation.
    class OneOffService < BaseService
      Result = BaseResult[:billing_items]

      ADD_ONS_KEY = "addons"

      def initialize(quote_version:)
        @quote_version = quote_version
        super
      end

      def call
        return result.not_found_failure!(resource: "add_on") unless add_ons_resolved?

        result.billing_items = billing_items
          .merge(ADD_ONS_KEY => add_on_array.map { |item| snapshot_item(item) })
        result
      end

      private

      attr_reader :quote_version

      delegate :organization, to: :quote_version

      def add_ons_resolved?
        add_on_array.all? { |item| add_ons_by_id.key?(item[:id].to_s) }
      end

      def snapshot_item(item)
        item.merge("payload" => frozen_payload(item, add_ons_by_id[item[:id].to_s]))
      end

      def frozen_payload(item, add_on)
        payload = item[:payload] || {}

        payload.merge(
          "code" => add_on.code,
          "name" => add_on.name,
          "invoice_display_name" => add_on.invoice_display_name,
          "description" => add_on.description,
          "unit_amount_cents" => add_on.amount_cents
        )
      end

      def add_ons_by_id
        @add_ons_by_id ||= organization.add_ons.with_discarded
          .where(id: add_on_ids).index_by { |add_on| add_on.id.to_s }
      end

      def add_on_ids
        add_on_array.filter_map { |item| item[:id] }.uniq
      end

      def add_on_array
        @add_on_array ||= billing_items[ADD_ONS_KEY] || []
      end

      def billing_items
        @billing_items ||= (quote_version.billing_items || {}).with_indifferent_access
      end
    end
  end
end
