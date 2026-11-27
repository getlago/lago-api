# frozen_string_literal: true

module CopyToProduction
  module Items
    # A category is copied with every product in it: products already live are reused, the others copied after it.
    class ProductCategoryItem < BaseItem
      ATTRIBUTES = %i[name code description invoice_display_name].freeze

      def children(source)
        source.products.sort_by(&:code).map { ["product", it] }
      end

      def copy!(source, _resolved)
        ProductCategories::CreateService.call!(
          organization: production,
          params: source.slice(*ATTRIBUTES)
        ).product_category
      end
    end
  end
end
