# frozen_string_literal: true

module CopyToProduction
  module Items
    # A category is copied with every product in it: products already live are reused, the others copied after it.
    class ProductCategoryItem < BaseItem
      ATTRIBUTES = %i[name code description invoice_display_name].freeze

      def find_source(id)
        sandbox.product_categories.includes(products: ProductItem::PRELOADS).find_by(id:)
      end

      def find_existing(source)
        production.product_categories.find_by(code: source.code)
      end

      def children(source)
        source.products.sort_by(&:code).map { ["product", it] }
      end

      def copy!(source, _resolved)
        ProductCategories::CreateService.call!(
          organization: production,
          params: source.slice(*ATTRIBUTES)
        ).product_category
      end

      def unique_indexes
        {"index_product_categories_on_organization_id_and_code" => :code}
      end
    end
  end
end
