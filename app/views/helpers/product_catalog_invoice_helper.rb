# frozen_string_literal: true

class ProductCatalogInvoiceHelper
  Line = Data.define(:name, :amount_cents)
  ContractBlock = Data.define(:title, :sections)
  Section = Data.define(:name, :amount_cents, :products)
  ProductNode = Data.define(:name, :amount_cents, :fees, :filters)
  FilterNode = Data.define(:name, :fees)
  Tier = Data.define(:label, :units, :unit_price, :amount)
  AmountDetails = Data.define(:attributes) do
    delegate :blank?, to: :attributes

    def graduated?
      ranges.present?
    end

    def percentage_ranges?
      attributes.key?("graduated_percentage_ranges")
    end

    def ranges
      attributes["graduated_ranges"] || attributes["graduated_percentage_ranges"]
    end

    def decimal(key)
      attributes[key].to_d
    end

    delegate :[], to: :attributes
  end

  Row = Data.define(:kind, :indent, :label, :units, :unit_price, :amount) do
    def initialize(units: nil, unit_price: nil, amount: nil, **)
      super
    end
  end

  RANGE_LABEL_KEYS = {
    fee: {
      first: "invoice.tiers.fee_for_first",
      next: "invoice.tiers.fee_for_next",
      remaining: "invoice.tiers.fee_for_remaining"
    },
    flat_fee: {
      first: "invoice.tiers.flat_fee_for_first",
      next: "invoice.tiers.flat_fee_for_next",
      remaining: "invoice.tiers.flat_fee_for_remaining"
    }
  }.freeze

  def self.summary_lines(invoice)
    new(invoice).summary_lines
  end

  def self.contract_blocks(invoice)
    new(invoice).contract_blocks
  end

  def self.contract_name(contract)
    contract.name.presence || contract.catalog_plan&.invoice_display_name.presence || contract.catalog_plan&.name
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
    details = AmountDetails.new(attributes: fee.amount_details || {})
    return [] if fee.true_up_parent_fee_id || details.blank?
    return graduated_tiers(fee, details) if details.graduated?

    case fee.rate_model
    when "volume" then volume_tiers(fee, details)
    when "package" then package_tiers(fee, details)
    when "percentage" then percentage_tiers(fee, details)
    else []
    end
  end

  def self.graduated_tiers(fee, details)
    per_unit = details.ranges.map do |range|
      unit_price = if details.percentage_ranges?
        FeeDisplayHelper.format_percentage_rate(range["rate"])
      else
        FeeDisplayHelper.format_with_precision(fee, range["per_unit_amount"])
      end

      Tier.new(
        label: range_label(:fee, range),
        units: RoundingHelper.round_decimal_part(range["units"].to_d),
        unit_price:,
        amount: FeeDisplayHelper.format_as_currency(fee, range["per_unit_total_amount"])
      )
    end

    flat = details.ranges.select { it["flat_unit_amount"].to_d.positive? }.map do |range|
      flat_amount = FeeDisplayHelper.format_as_currency(fee, range["flat_unit_amount"])
      Tier.new(label: range_label(:flat_fee, range), units: 1, unit_price: flat_amount, amount: flat_amount)
    end

    per_unit + flat
  end

  # Without a flat fee, the per-unit line would repeat the period line.
  def self.volume_tiers(fee, details)
    if details.decimal("flat_unit_amount").positive?
      flat_amount = FeeDisplayHelper.format_as_currency(fee, details["flat_unit_amount"])
      [
        Tier.new(
          label: I18n.t("invoice.volume.fee_per_unit"),
          units: RoundingHelper.round_decimal_part(fee.units),
          unit_price: FeeDisplayHelper.format_with_precision(fee, details["per_unit_amount"]),
          amount: FeeDisplayHelper.format_as_currency(fee, details["per_unit_total_amount"])
        ),
        Tier.new(label: I18n.t("invoice.volume.flat_fee_for_all_units"), units: 1, unit_price: flat_amount, amount: flat_amount)
      ]
    else
      []
    end
  end

  def self.package_tiers(fee, details)
    free_units = details.decimal("free_units")
    tiers = []

    if free_units.positive?
      rounded_free_units = RoundingHelper.round_decimal_part(free_units)
      tiers << free_tier(fee, I18n.t("invoice.package.free_units_for_the_first", count: rounded_free_units), rounded_free_units)
    end

    tiers << Tier.new(
      label: I18n.t("invoice.package.fee_per_package"),
      units: RoundingHelper.round_decimal_part(details.decimal("paid_units")),
      unit_price: I18n.t(
        "invoice.package.fee_per_package_unit_price",
        amount: FeeDisplayHelper.format_with_precision(fee, details["per_package_unit_amount"]),
        package_size: details["per_package_size"]
      ),
      amount: FeeDisplayHelper.format_amount(fee)
    )
  end

  def self.percentage_tiers(fee, details)
    free_units = details.decimal("free_units")
    tiers = []

    if free_units.positive?
      label = I18n.t("invoice.percentage.free_units_per_transaction", count: details["free_events"].to_i)
      tiers << free_tier(fee, label, RoundingHelper.round_decimal_part(free_units))
    end

    tiers << Tier.new(
      label: I18n.t("invoice.percentage.percentage_rate_on_amount"),
      units: RoundingHelper.round_decimal_part(details.decimal("paid_units")),
      unit_price: FeeDisplayHelper.format_percentage_rate(details["rate"]),
      amount: FeeDisplayHelper.format_as_currency(fee, details["per_unit_total_amount"])
    )

    if details.decimal("fixed_fee_unit_amount").positive?
      tiers << Tier.new(
        label: I18n.t("invoice.percentage.fee_per_transaction"),
        units: details["paid_events"].to_i,
        unit_price: FeeDisplayHelper.format_as_currency(fee, details["fixed_fee_unit_amount"]),
        amount: FeeDisplayHelper.format_as_currency(fee, details["fixed_fee_total_amount"])
      )
    end

    unless details.decimal("min_max_adjustment_total_amount").zero?
      adjustment = FeeDisplayHelper.format_as_currency(fee, details["min_max_adjustment_total_amount"])
      tiers << Tier.new(label: I18n.t("invoice.percentage.adjustment_per_transaction"), units: 1, unit_price: adjustment, amount: adjustment)
    end

    tiers
  end

  def self.free_tier(fee, label, units)
    zero = FeeDisplayHelper.format_as_currency(fee, 0)
    Tier.new(label:, units:, unit_price: zero, amount: zero)
  end

  def self.detail_rows(section, currency)
    depth = section.name ? 1 : 0
    rows = section.name ? [Row.new(kind: :category, indent: 0, label: section.name, amount: format_cents(section.amount_cents, currency))] : []

    section.products.each do |product|
      rows << Row.new(kind: :product, indent: depth, label: product.name, amount: format_cents(product.amount_cents, currency))
      rows.concat(fee_rows(product.fees, depth + 1))

      product.filters.each do |filter|
        rows << Row.new(kind: :filter, indent: depth + 1, label: filter.name)
        rows.concat(fee_rows(filter.fees, depth + 2))
      end
    end

    rows
  end

  def self.fee_rows(fees, indent)
    fees.flat_map do |fee|
      segment = Row.new(
        kind: :segment,
        indent:,
        label: period_label(fee),
        units: RoundingHelper.round_decimal_part(fee.units),
        unit_price: unbreakable(FeeDisplayHelper.format_precise_unit_amount(fee)),
        amount: unbreakable(FeeDisplayHelper.format_amount(fee))
      )
      conversion = conversion_row(fee, indent + 1)
      detail_indent = conversion ? indent + 2 : indent + 1
      details = tiers(fee).map do |tier|
        Row.new(
          kind: :fee_detail,
          indent: detail_indent,
          label: tier.label,
          units: tier.units,
          unit_price: unbreakable(tier.unit_price),
          amount: unbreakable(tier.amount)
        )
      end

      [segment, conversion, *details].compact
    end
  end

  def self.conversion_row(fee, indent)
    usage = fee.pricing_unit_usage

    if usage
      rate = MoneyHelper.format_with_precision(usage.conversion_rate, fee.amount_currency)
      Row.new(
        kind: :conversion,
        indent:,
        label: "#{I18n.t("invoice.conversion_rate")}: 1 #{usage.short_name} = #{rate}",
        amount: unbreakable(MoneyHelper.format(fee.amount))
      )
    end
  end

  def self.unbreakable(value)
    value.to_s.tr(" ", "\u00A0")
  end

  def self.format_cents(amount_cents, currency)
    MoneyHelper.format(Money.new(amount_cents, currency))
  end

  def self.range_label(kind, range)
    position = if range["to_value"].nil?
      :remaining
    elsif range["from_value"].to_d.zero?
      :first
    else
      :next
    end

    I18n.t(RANGE_LABEL_KEYS.fetch(kind).fetch(position), up_to: range["to_value"])
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

  # An invoice billed on event reception holds a single pay-in-advance fee.
  def single_event_fee?
    !invoice.advance_charges? && product_fees.one? && product_fees.first.pay_in_advance_event_transaction_id.present?
  end

  def contract_blocks
    product_fees.group_by(&:contract).sort_by { |contract, _| contract_name(contract).to_s.downcase }.map do |contract, fees|
      ContractBlock.new(title: contract_title(contract), sections: sections(fees))
    end
  end

  private

  attr_reader :invoice

  def product_fees
    @product_fees ||= invoice.fees.product.includes(:product_filter, :pricing_unit_usage, :rate_card_rate, :rate_override, invoice: :customer, contract: :catalog_plan, true_up_parent_fee: [:product_filter, :invoiceable]).to_a
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

      ProductNode.new(
        name: product.invoice_name,
        amount_cents: product_fees.sum(&:amount_cents),
        fees: by_period(unfiltered),
        filters: sort_by_name(filters)
      )
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
    self.class.contract_name(contract)
  end

  def contract_title(contract)
    purchase_order_number = invoice.purchase_order_number.presence || contract.purchase_order_number
    [contract_name(contract), "#{invoice.document_invoice_name} #{invoice.number}", purchase_order_number.presence].compact.join(" - ")
  end
end
