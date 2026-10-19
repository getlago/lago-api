# frozen_string_literal: true

class ProductCatalogInvoiceHelper
  Line = Data.define(:name, :amount_cents)
  ContractBlock = Data.define(:title, :sections)
  Section = Data.define(:name, :amount_cents, :products)
  ProductNode = Data.define(:name, :fees, :filters)
  FilterNode = Data.define(:name, :fees)
  Tier = Data.define(:label, :units, :unit_price, :amount)

  def self.summary_lines(invoice)
    new(invoice).summary_lines
  end

  def self.contract_blocks(invoice)
    new(invoice).contract_blocks
  end

  def self.period_label(fee)
    from_datetime, to_datetime = fee.properties.values_at("from_datetime", "to_datetime")

    if fee.true_up_parent_fee_id
      I18n.t("invoice.true_up_metric", metric: fee.true_up_parent_fee.invoice_name)
    elsif from_datetime.blank? || to_datetime.blank?
      ""
    else
      timezone = fee.invoice.customer.applicable_timezone
      from_date = Time.zone.parse(from_datetime).in_time_zone(timezone).to_date
      to_date = Time.zone.parse(to_datetime).in_time_zone(timezone).to_date

      I18n.t("invoice.from_to_date", from_date: I18n.l(from_date, format: "%-d %b"), to_date: I18n.l(to_date, format: "%-d %b %Y"))
    end
  end

  def self.tiers(fee)
    return [] if fee.true_up_parent_fee_id

    percentage = fee.amount_details.key?("graduated_percentage_ranges")
    ranges = fee.amount_details["graduated_ranges"] || fee.amount_details["graduated_percentage_ranges"] || []

    per_unit = ranges.map do |range|
      unit_price = if percentage
        FeeDisplayHelper.format_percentage_rate(range["rate"])
      else
        FeeDisplayHelper.format_with_precision(fee, range["per_unit_amount"])
      end

      Tier.new(
        label: range_label("fee_per_unit", range),
        units: RoundingHelper.round_decimal_part(range["units"].to_d),
        unit_price:,
        amount: FeeDisplayHelper.format_as_currency(fee, range["per_unit_total_amount"])
      )
    end

    flat = ranges.select { it["flat_unit_amount"].to_d.positive? }.map do |range|
      flat_amount = FeeDisplayHelper.format_as_currency(fee, range["flat_unit_amount"])
      Tier.new(label: range_label("flat_fee", range), units: 1, unit_price: flat_amount, amount: flat_amount)
    end

    per_unit + flat
  end

  def self.range_label(kind, range)
    position = if range["to_value"].nil?
      "last"
    elsif range["from_value"].to_d.zero?
      "first"
    else
      "next"
    end

    I18n.t("invoice.graduated.#{kind}_for_the_#{position}", from: range["from_value"], to: range["to_value"])
  end

  def initialize(invoice)
    @invoice = invoice
  end

  def summary_lines
    by_category = product_fees.group_by { category_for(it) }
    standalone_fees = by_category.delete(nil) || []

    category_lines = by_category.map { |category, fees| Line.new(name: category.invoice_name, amount_cents: fees.sum(&:amount_cents)) }
    product_lines = standalone_fees.group_by { product_for(it) }.map do |product, fees|
      Line.new(name: product.invoice_name, amount_cents: fees.sum(&:amount_cents))
    end

    sort_by_name(category_lines) + sort_by_name(product_lines)
  end

  def contract_blocks
    product_fees.group_by(&:contract).sort_by { |contract, _| contract_name(contract).to_s.downcase }.map do |contract, fees|
      ContractBlock.new(title: contract_title(contract), sections: sections(fees))
    end
  end

  private

  attr_reader :invoice

  def product_fees
    @product_fees ||= invoice.fees.product.includes(:product_filter, :pricing_unit_usage, invoice: :customer, contract: :catalog_plan, true_up_parent_fee: [:product_filter, :invoiceable]).to_a
  end

  def products
    @products ||= Product.with_discarded.where(organization_id: invoice.organization_id, id: product_fees.map(&:invoiceable_id)).index_by(&:id)
  end

  def categories
    @categories ||= ProductCategory.with_discarded
      .where(organization_id: invoice.organization_id, id: products.values.map(&:product_category_id))
      .index_by(&:id)
  end

  def product_for(fee)
    products[fee.invoiceable_id]
  end

  def category_for(fee)
    categories[product_for(fee).product_category_id]
  end

  def sections(fees)
    by_category = fees.group_by { category_for(it) }
    standalone_fees = by_category.delete(nil)

    categorized = by_category.sort_by { |category, _| category.invoice_name.downcase }.map do |category, category_fees|
      Section.new(name: category.invoice_name, amount_cents: category_fees.sum(&:amount_cents), products: product_nodes(category_fees))
    end
    return categorized if standalone_fees.blank?

    categorized + [Section.new(name: nil, amount_cents: standalone_fees.sum(&:amount_cents), products: product_nodes(standalone_fees))]
  end

  def product_nodes(fees)
    nodes = fees.group_by { product_for(it) }.map do |product, product_fees|
      unfiltered, filtered = product_fees.partition { filter_for(it).nil? }
      filters = filtered.group_by { filter_for(it) }.map { |filter, filter_fees| FilterNode.new(name: filter.invoice_name, fees: by_period(filter_fees)) }

      ProductNode.new(name: product.invoice_name, fees: by_period(unfiltered), filters: sort_by_name(filters))
    end

    sort_by_name(nodes)
  end

  # A true-up fee carries no filter of its own; it belongs with the fee it tops up.
  def filter_for(fee)
    (fee.true_up_parent_fee || fee).product_filter
  end

  # Each true-up follows the fee it tops up.
  def by_period(fees)
    fees.sort_by do |fee|
      parent = fee.true_up_parent_fee || fee
      [parent.properties["from_datetime"].to_s, parent.id, fee.true_up_parent_fee_id ? 1 : 0]
    end
  end

  def sort_by_name(items)
    items.sort_by { it.name.downcase }
  end

  def contract_name(contract)
    contract.name.presence || contract.catalog_plan&.invoice_display_name.presence || contract.catalog_plan&.name
  end

  def contract_title(contract)
    purchase_order_number = invoice.purchase_order_number.presence || contract.purchase_order_number
    [contract_name(contract), "#{invoice.document_invoice_name} #{invoice.number}", purchase_order_number.presence].compact.join(" - ")
  end
end
