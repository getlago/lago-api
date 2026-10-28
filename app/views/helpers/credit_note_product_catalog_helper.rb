# frozen_string_literal: true

class CreditNoteProductCatalogHelper
  Line = Data.define(:name, :amount_cents)
  ContractBlock = Data.define(:title, :sections)
  Section = Data.define(:name, :amount_cents, :products)
  ProductNode = Data.define(:name, :amount_cents, :items, :filters)
  FilterNode = Data.define(:name, :items)
  Row = Data.define(:kind, :indent, :label, :amount) do
    def initialize(indent: nil, amount: nil, **)
      super
    end
  end
  CreditedItem = Data.define(:item, :fee)

  def self.summary_lines(credit_note)
    new(credit_note).summary_lines
  end

  def self.contract_blocks(credit_note)
    new(credit_note).contract_blocks
  end

  def self.detail_rows(section, currency)
    depth = section.name ? 1 : 0
    rows = if section.name
      [Row.new(kind: :category, indent: 0, label: section.name, amount: format_cents(section.amount_cents, currency))]
    else
      []
    end

    section.products.each do |product|
      rows << Row.new(kind: :product, indent: depth, label: product.name, amount: format_cents(product.amount_cents, currency))
      rows.concat(item_rows(product.items, depth + 1))

      product.filters.each do |filter|
        rows << Row.new(kind: :filter, indent: depth + 1, label: filter.name)
        rows.concat(item_rows(filter.items, depth + 2))
      end
    end

    rows
  end

  def initialize(credit_note)
    @credit_note = credit_note
  end

  def summary_lines
    ProductCatalogHierarchyHelper.summary_groups(hierarchy_entries).map { Line.new(name: it.name, amount_cents: it.amount_cents) }
  end

  def contract_blocks
    ProductCatalogHierarchyHelper.contract_groups(hierarchy_entries).map do |group|
      ContractBlock.new(title: contract_title(group.contract), sections: sections(group.sections))
    end
  end

  private

  attr_reader :credit_note

  def credited_items
    @credited_items ||= begin
      items = CreditNoteDetailsHelper::ContractRows.load(credit_note)
      fees = items.map(&:fee)
      if fees.any?
        ActiveRecord::Associations::Preloader.new(
          records: fees,
          associations: [
            {contract: :catalog_plan},
            {invoice: :customer},
            {true_up_parent_fee: [:product_filter, :invoiceable]}
          ]
        ).call
      end

      items.map { |item| CreditedItem.new(item:, fee: item.fee) }
    end
  end

  def products
    @products ||= Product.with_discarded
      .where(organization_id: credit_note.organization_id, id: credited_items.map { it.fee.invoiceable_id }.uniq)
      .index_by(&:id)
  end

  def categories
    @categories ||= ProductCategory.with_discarded
      .where(organization_id: credit_note.organization_id, id: products.values.map(&:product_category_id).compact.uniq)
      .index_by(&:id)
  end

  def filters
    filter_ids = credited_items.flat_map do |credited|
      [credited.fee.product_filter_id, credited.fee.true_up_parent_fee&.product_filter_id]
    end.compact.uniq

    @filters ||= ProductFilter.with_discarded
      .where(organization_id: credit_note.organization_id, id: filter_ids)
      .index_by(&:id)
  end

  def product_for(fee)
    products[fee.invoiceable_id]
  end

  def filter_for(fee)
    parent = fee.true_up_parent_fee
    filters[parent&.product_filter_id || fee.product_filter_id]
  end

  def hierarchy_entries
    @hierarchy_entries ||= credited_items.map do |credited|
      fee = credited.fee
      product = product_for(fee)
      ProductCatalogHierarchyHelper::Entry.new(
        fee:, source: credited.item, amount_cents: credited.item.amount_cents, contract: fee.contract,
        product:, category: categories[product&.product_category_id], filter: filter_for(fee)
      )
    end
  end

  def sections(groups)
    groups.map do |group|
      Section.new(
        name: group.category&.invoice_name,
        amount_cents: ProductCatalogHierarchyHelper.total(group.entries),
        products: group.products.map do |product_group|
          ProductNode.new(
            name: product_group.product.invoice_name,
            amount_cents: ProductCatalogHierarchyHelper.total(product_group.entries),
            items: product_group.unfiltered_entries.map { credited_item(it) },
            filters: product_group.filters.map do |filter_group|
              FilterNode.new(name: filter_group.filter.invoice_name, items: filter_group.entries.map { credited_item(it) })
            end
          )
        end
      )
    end
  end

  def credited_item(entry)
    CreditedItem.new(item: entry.source, fee: entry.fee)
  end

  def self.item_rows(items, indent)
    items.map do |credited|
      label = ProductCatalogInvoiceHelper.period_label(credited.fee).presence || credited.fee.invoice_name

      Row.new(
        kind: :segment,
        indent:,
        label:,
        amount: MoneyHelper.format(credited.item.amount)
      )
    end
  end

  def self.format_cents(amount_cents, currency)
    MoneyHelper.format(Money.new(amount_cents, currency))
  end

  private_class_method :item_rows, :format_cents

  def contract_title(contract)
    invoice = credit_note.invoice
    purchase_order_number = invoice.purchase_order_number.presence || contract.purchase_order_number
    [contract_name(contract), "#{I18n.t("credit_note.document_name")} #{credit_note.number}", purchase_order_number.presence].compact.join(" - ")
  end

  def contract_name(contract)
    contract.name.presence || contract.catalog_plan&.invoice_display_name.presence || contract.catalog_plan&.name
  end
end
