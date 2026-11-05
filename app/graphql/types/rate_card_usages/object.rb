# frozen_string_literal: true

module Types
  module RateCardUsages
    class Object < Types::BaseObject
      graphql_name "RateCardUsage"
      description "One rate card's computed usage on a contract's current billing window"

      field :amount_cents, GraphQL::Types::BigInt, null: false
      field :billable_metric_code, String, null: true
      field :billing_timing, String, null: false
      field :events_count, Integer, null: false
      field :from_datetime, GraphQL::Types::ISO8601DateTime, null: false
      field :invoice_display_name, String, null: false
      field :product_category_code, String, null: true
      field :product_category_name, String, null: true
      field :product_code, String, null: false
      field :product_filter_code, String, null: true
      field :product_filter_name, String, null: true
      field :product_name, String, null: false
      field :product_type, Types::Products::ProductTypeEnum, null: false
      field :rate_card_code, String, null: false
      field :rate_card_name, String, null: false
      field :rate_phase_code, String, null: true
      field :rate_phase_name, String, null: true
      field :rate_source, String, null: false
      field :to_datetime, GraphQL::Types::ISO8601DateTime, null: false
      field :units, GraphQL::Types::Float, null: false

      delegate :code, to: :rate_card, prefix: true

      delegate :name, to: :rate_card, prefix: true

      delegate :code, to: :product, prefix: true

      delegate :name, to: :product, prefix: true

      def product_category_code = product.product_category&.code

      def product_category_name = product.product_category&.name

      def product_filter_code = product_filter&.code

      def product_filter_name = product_filter&.name

      def invoice_display_name = (product_filter || product).invoice_name

      delegate :product_type, to: :product

      def billable_metric_code = product.billable_metric&.code

      delegate :billing_timing, to: :rate_card

      def rate_phase_code = object.rate_phase&.code

      def rate_phase_name = object.rate_phase&.name

      delegate :rate_source, to: :object

      def units = object.units.to_f

      delegate :events_count, to: :object

      delegate :amount_cents, to: :object

      def from_datetime = object.billing_segment.started_at

      def to_datetime = object.billing_segment.ended_at

      private

      def rate_card = object.contract_rate_card.rate_card

      def product = rate_card.product

      def product_filter = rate_card.product_filter
    end
  end
end
