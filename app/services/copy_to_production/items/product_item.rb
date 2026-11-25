# frozen_string_literal: true

module CopyToProduction
  module Items
    # A product is copied with its filters and its rate cards, once its category is live.
    class ProductItem < BaseItem
      ATTRIBUTES = %i[name code description invoice_display_name product_type].freeze
      # Reused only from the live category with the code of its own: a live product with its code elsewhere refuses
      # the copy.
      def find_existing(source)
        live_product = production.products.find_by(code: source.code)
        live_product if live_product&.product_category&.code == source.product_category&.code
      end

      # A deleted metric is never brought along: the product refuses the copy instead.
      def dependencies(source)
        (source.billable_metric && !source.billable_metric.discarded?) ? [["billable_metric", source.billable_metric]] : []
      end

      def parent(source)
        ["product_category", source.product_category] if source.product_category
      end

      def refusal(source)
        "copy_to_production_target_deleted" if source.billable_metric&.discarded?
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

        # Filter precedence breaks ties by age, so production gets them in the sandbox's creation order.
        source.filters.sort_by { [it.created_at, it.id] }.each { copy_filter!(product, it) }
        product
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
