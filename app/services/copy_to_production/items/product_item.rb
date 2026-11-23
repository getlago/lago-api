# frozen_string_literal: true

module CopyToProduction
  module Items
    # A product is copied with its filters and its rate cards, once its category is live.
    class ProductItem < BaseItem
      ATTRIBUTES = %i[name code description invoice_display_name product_type].freeze
      PRELOADS = [
        :billable_metric,
        {filters: {values: :billable_metric_filter}},
        {rate_cards: RateCardItem::PRELOADS}
      ].freeze

      def find_source(id)
        sandbox.products.includes(:product_category, *PRELOADS).find_by(id:)
      end

      def find_existing(source)
        production.products.find_by(code: source.code)
      end

      def dependencies(source)
        source.billable_metric ? [["billable_metric", source.billable_metric]] : []
      end

      def parent(source)
        ["product_category", source.product_category] if source.product_category
      end

      # A product filter names its metric's filters by key and value, which a reused production metric may lack.
      def refusal(source)
        "copy_to_production_filter_missing" if source.billable_metric && source.filters.any? && missing_metric_filter?(source)
      end

      def children(source)
        source.rate_cards.sort_by(&:code).map { ["rate_card", it] }
      end

      def copy!(source, resolved)
        product = Products::CreateService.call!(
          organization: production,
          params: source.slice(*ATTRIBUTES).merge(
            product_category_id: source.product_category && resolved.fetch(["product_category", source.product_category_id]).id,
            billable_metric_id: source.billable_metric && resolved.fetch(["billable_metric", source.billable_metric_id]).id
          )
        ).product

        source.filters.sort_by(&:code).each { copy_filter!(product, it) }
        product
      end

      def unique_indexes
        {"index_products_on_organization_id_and_code" => :code}
      end

      private

      def missing_metric_filter?(source)
        live_metric = production.billable_metrics.includes(:filters).find_by(code: source.billable_metric.code)
        return false unless live_metric

        live_values = live_metric.filters.to_h { [it.key, it.values] }
        source.filters.flat_map(&:values).any? do |value|
          values = live_values[value.billable_metric_filter.key]
          values.nil? || (!value.value.nil? && values.exclude?(value.value))
        end
      end

      # Values name the metric filter by key, which ProductFilters::CreateService resolves on the production metric.
      def copy_filter!(product, filter)
        ProductFilters::CreateService.call!(
          product:,
          params: filter.slice(:name, :code, :description, :invoice_display_name).merge(
            values: filter.values.map { {key: it.billable_metric_filter.key, value: it.value} }
          )
        )
      end
    end
  end
end
