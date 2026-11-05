# frozen_string_literal: true

module Invoices
  # The contract > category > product > filter tree of an invoice's product fees, with the amount and
  # the fee count of each product and filter, in the order of the catalog invoice PDF. It sums in SQL
  # rather than loading the fees, which the invoice page lists a page at a time.
  class ProductCatalogTreeService < BaseService
    Result = BaseResult[:contracts]

    ContractGroup = Data.define(:contract, :sections)
    Section = Data.define(:category, :products)
    ProductGroup = Data.define(:product, :amount_cents, :fees_count, :filters)
    FilterGroup = Data.define(:filter, :amount_cents, :fees_count)
    Total = Data.define(:contract_id, :product_id, :filter_id, :amount_cents, :fees_count)

    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      result.contracts = totals.group_by(&:contract_id).map { |contract_id, rows| contract_group(contracts[contract_id], rows) }
        .sort_by { [ProductCatalogInvoiceHelper.contract_name(it.contract).to_s.downcase, it.contract.id] }
      result
    end

    private

    attr_reader :invoice

    # A true-up carries no filter of its own: it counts under the filter of the fee it tops up.
    def totals
      @totals ||= invoice.fees.product.where.not(contract_id: nil)
        .joins("LEFT JOIN fees AS parent_fees ON parent_fees.id = fees.true_up_parent_fee_id")
        .group(:contract_id, :invoiceable_id, Arel.sql("COALESCE(fees.product_filter_id, parent_fees.product_filter_id)"))
        .pluck(
          :contract_id,
          :invoiceable_id,
          Arel.sql("COALESCE(fees.product_filter_id, parent_fees.product_filter_id)"),
          Arel.sql("SUM(fees.amount_cents)"),
          Arel.sql("COUNT(*)")
        )
        .map { Total.new(*it) }
    end

    def contract_group(contract, rows)
      sections = rows.group_by { products[it.product_id].product_category_id }.map do |category_id, category_rows|
        Section.new(category: categories[category_id], products: product_groups(category_rows))
      end

      ContractGroup.new(contract:, sections: sections.sort_by { [it.category ? 0 : 1, *sort_key(it.category)] })
    end

    def product_groups(rows)
      rows.group_by(&:product_id).map do |product_id, product_rows|
        filters = product_rows.select(&:filter_id).map do |row|
          FilterGroup.new(filter: filters_by_id[row.filter_id], amount_cents: row.amount_cents, fees_count: row.fees_count)
        end

        ProductGroup.new(
          product: products[product_id],
          amount_cents: product_rows.sum(&:amount_cents),
          fees_count: product_rows.sum(&:fees_count),
          filters: filters.sort_by { sort_key(it.filter) }
        )
      end.sort_by { sort_key(it.product) }
    end

    def sort_key(record)
      [record&.invoice_name.to_s.downcase, record&.id.to_s]
    end

    def contracts
      @contracts ||= Contract.where(organization_id: invoice.organization_id, id: totals.map(&:contract_id)).includes(:catalog_plan).index_by(&:id)
    end

    def products
      @products ||= Product.with_discarded.where(organization_id: invoice.organization_id, id: totals.map(&:product_id)).index_by(&:id)
    end

    def categories
      @categories ||= ProductCategory.with_discarded
        .where(organization_id: invoice.organization_id, id: products.values.map(&:product_category_id))
        .index_by(&:id)
    end

    def filters_by_id
      @filters_by_id ||= ProductFilter.with_discarded.where(organization_id: invoice.organization_id, id: totals.map(&:filter_id).compact).index_by(&:id)
    end
  end
end
