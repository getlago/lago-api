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
