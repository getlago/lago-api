# frozen_string_literal: true

# The product fees of an invoice, a page at a time, in the order of the catalog invoice PDF
# (ProductCatalogHierarchyHelper): contract, category (standalone products last), product,
# filter (unfiltered fees first), then period, each true-up right after the fee it tops up.
class InvoiceProductFeesQuery < BaseQuery
  Result = BaseResult[:fees]
  Filters = BaseFilters[
    :invoice_id,
    :contract_id,
    :product_category_id,
    :standalone_products,
    :product_ids,
    :product_filter_ids,
    :without_product_filter,
    :product_type
  ]

  DEFAULT_LIMIT = 100
  MAX_LIMIT = 100

  def call
    return result.not_found_failure!(resource: "invoice") unless invoice

    # The column is a PG enum: an unknown value would fail the SQL cast.
    if filters.product_type.present? && !Product::PRODUCT_TYPES.value?(filters.product_type)
      return result.single_validation_failure!(
        field: :product_type,
        error_code: "value_is_invalid",
        meta: {allowed_values: Product::PRODUCT_TYPES.values}
      )
    end

    fees = base_scope
    fees = with_contract(fees) unless filters.contract_id.nil?
    fees = with_product_category(fees) unless filters.product_category_id.nil?
    fees = fees.where(products: {product_category_id: nil}) if standalone_products?
    fees = with_products(fees) unless filters.product_ids.nil?
    fees = with_product_filter(fees) if !filters.product_filter_ids.nil? || without_product_filter?
    fees = fees.where("products.product_type = ?", filters.product_type) if filters.product_type.present?
    fees = with_search_term(fees) if search_term.present?

    result.fees = paginate(ordered(fees))
    result
  end

  private

  def invoice
    @invoice ||= organization.invoices.visible.find_by(id: filters.invoice_id)
  end

  # Raw joins keep the discarded products, categories and filters a fee was billed for. A true-up
  # carries no filter of its own and takes the one of the fee it tops up.
  def base_scope
    invoice.fees.product
      .joins("INNER JOIN products ON products.id = fees.invoiceable_id")
      .joins("LEFT JOIN product_categories ON product_categories.id = products.product_category_id")
      .joins("INNER JOIN contracts ON contracts.id = fees.contract_id")
      .joins("LEFT JOIN catalog_plans ON catalog_plans.id = contracts.catalog_plan_id")
      .joins("LEFT JOIN fees AS parent_fees ON parent_fees.id = fees.true_up_parent_fee_id")
      .joins("LEFT JOIN product_filters ON product_filters.id = COALESCE(fees.product_filter_id, parent_fees.product_filter_id)")
  end

  def with_contract(scope)
    scope.where("fees.contract_id IN (?)", uuids(filters.contract_id))
  end

  def with_product_category(scope)
    scope.where("products.product_category_id IN (?)", uuids(filters.product_category_id))
  end

  def with_products(scope)
    scope.where("fees.invoiceable_id IN (?)", uuids(filters.product_ids))
  end

  # A multi-select: the chosen filters OR "no filter".
  def with_product_filter(scope)
    ids = uuids(filters.product_filter_ids)

    if without_product_filter?
      scope.where("product_filters.id IN (?) OR product_filters.id IS NULL", ids)
    else
      scope.where("product_filters.id IN (?)", ids)
    end
  end

  def with_search_term(scope)
    scope.where(
      "products.name ILIKE :term OR products.code ILIKE :term OR products.invoice_display_name ILIKE :term " \
      "OR product_filters.name ILIKE :term OR product_filters.code ILIKE :term OR product_filters.invoice_display_name ILIKE :term",
      term: "%#{Fee.sanitize_sql_like(search_term)}%"
    )
  end

  # The names compare bytewise (COLLATE "C"), as the PDF and the tree compare them in Ruby, whatever the
  # collation of the database. A blank name falls back as `.presence` does there, and a contract without
  # a name or a plan sorts as an empty name, first.
  def ordered(scope)
    scope.order(
      Arel.sql("LOWER(COALESCE(NULLIF(BTRIM(contracts.name), ''), NULLIF(BTRIM(catalog_plans.invoice_display_name), ''), catalog_plans.name, '')) COLLATE \"C\""),
      Arel.sql("contracts.id"),
      Arel.sql("product_categories.id IS NULL"),
      Arel.sql("LOWER(COALESCE(NULLIF(BTRIM(product_categories.invoice_display_name), ''), product_categories.name)) COLLATE \"C\""),
      Arel.sql("product_categories.id"),
      Arel.sql("LOWER(COALESCE(NULLIF(BTRIM(products.invoice_display_name), ''), products.name)) COLLATE \"C\""),
      Arel.sql("products.id"),
      Arel.sql("product_filters.id IS NOT NULL"),
      Arel.sql("LOWER(COALESCE(NULLIF(BTRIM(product_filters.invoice_display_name), ''), product_filters.name)) COLLATE \"C\""),
      Arel.sql("product_filters.id"),
      Arel.sql("COALESCE(parent_fees.properties ->> 'from_datetime', fees.properties ->> 'from_datetime', '')"),
      Arel.sql("COALESCE(parent_fees.id, fees.id)"),
      Arel.sql("fees.true_up_parent_fee_id IS NOT NULL"),
      Arel.sql("fees.id")
    )
  end

  # A malformed id matches nothing rather than failing the UUID cast.
  def uuids(values)
    Array(values).map(&:to_s).grep(UUID_REGEX)
  end

  def standalone_products?
    ActiveModel::Type::Boolean.new.cast(filters.standalone_products)
  end

  def without_product_filter?
    ActiveModel::Type::Boolean.new.cast(filters.without_product_filter)
  end

  def pagination
    super&.tap { |pagination| pagination.limit = (pagination.limit || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT) }
  end
end
