# frozen_string_literal: true

# Orders applied rate cards the way the catalog groups them on screen: by
# product category, products outside any category last, then by product, a
# product's own card before its filter cards. Groups stay contiguous across
# pages, so a client groups consecutive rows. Outer joins keep every card: a
# card whose category was discarded falls with the standalone products, as
# its product then reports no category.
module RateCardCategoryOrdering
  private

  def order_by_product_category(scope)
    scope
      .left_outer_joins(rate_card: [:product_filter, {product: :product_category}])
      .order(Arel.sql("product_categories.name ASC NULLS LAST, product_categories.id ASC NULLS LAST"))
      .order(Arel.sql("products.name ASC, products.id ASC"))
      .order(Arel.sql("product_filters.name ASC NULLS FIRST, product_filters.id ASC NULLS FIRST"))
  end
end
