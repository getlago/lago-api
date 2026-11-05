# frozen_string_literal: true

module Types
  module RateCardUsages
    class Object < Types::BaseObject
      graphql_name "RateCardUsage"
      description "One rate card's computed usage on a contract's current billing window"

      field :rate_card_code, String, null: false
      field :rate_card_name, String, null: false
      field :product_code, String, null: false
      field :product_name, String, null: false
      field :product_category_code, String, null: true
      field :product_category_name, String, null: true
      field :product_filter_code, String, null: true
      field :product_filter_name, String, null: true
      field :invoice_display_name, String, null: false
      field :product_type, Types::Products::ProductTypeEnum, null: false
      field :billable_metric_code, String, null: true
      field :billing_timing, String, null: false
      field :rate_phase_code, String, null: true
      field :rate_phase_name, String, null: true
      field :rate_source, String, null: false
      field :units, GraphQL::Types::Float, null: false
      field :events_count, Integer, null: false
      field :amount_cents, GraphQL::Types::BigInt, null: false
      field :from_datetime, GraphQL::Types::ISO8601DateTime, null: false
      field :to_datetime, GraphQL::Types::ISO8601DateTime, null: false

      def rate_card_code = rate_card.code

      def rate_card_name = rate_card.name

      def product_code = product.code

      def product_name = product.name

      def product_category_code = product.product_category&.code

      def product_category_name = product.product_category&.name

      def product_filter_code = product_filter&.code

      def product_filter_name = product_filter&.name

      def invoice_display_name = (product_filter || product).invoice_name

      def product_type = product.product_type

      def billable_metric_code = product.billable_metric&.code

      def billing_timing = rate_card.billing_timing

      def rate_phase_code = object.rate_phase&.code

      def rate_phase_name = object.rate_phase&.name

      def rate_source = object.rate_source

      def units = object.units.to_f

      def events_count = object.events_count

      def amount_cents = object.amount_cents

      def from_datetime = object.billing_segment.started_at

      def to_datetime = object.billing_segment.ended_at

      private

      def rate_card = object.contract_rate_card.rate_card

      def product = rate_card.product

      def product_filter = rate_card.product_filter
    end
  end
end
