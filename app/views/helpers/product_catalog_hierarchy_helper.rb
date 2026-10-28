# frozen_string_literal: true

class ProductCatalogHierarchyHelper
  Entry = Data.define(:fee, :source, :amount_cents, :contract, :product, :category, :filter)
  SummaryGroup = Data.define(:name, :amount_cents)
  ContractGroup = Data.define(:contract, :sections)
  SectionGroup = Data.define(:category, :entries, :products)
  ProductGroup = Data.define(:name, :product, :entries, :unfiltered_entries, :filters)
  FilterGroup = Data.define(:name, :filter, :entries)

  def self.summary_groups(entries)
    by_category = entries.group_by(&:category)
    standalone = by_category.delete(nil) || []

    categories = by_category.map do |category, category_entries|
      SummaryGroup.new(name: category.invoice_name, amount_cents: total(category_entries))
    end
    products = standalone.group_by(&:product).map do |product, product_entries|
      SummaryGroup.new(name: product.invoice_name, amount_cents: total(product_entries))
    end

    sort_by_name(categories) + sort_by_name(products)
  end

  def self.contract_groups(entries)
    entries.group_by(&:contract).sort_by { |contract, _| contract_name(contract).to_s.downcase }.map do |contract, contract_entries|
      ContractGroup.new(contract:, sections: sections(contract_entries))
    end
  end

  def self.sections(entries)
    grouped = entries.group_by(&:category)
    uncategorized = grouped.delete(nil) || []
    categorized = grouped.sort_by { |category, _| category.invoice_name.downcase }.map do |category, category_entries|
      SectionGroup.new(category:, entries: category_entries, products: product_groups(category_entries))
    end

    categorized + (uncategorized.any? ? [SectionGroup.new(category: nil, entries: uncategorized, products: product_groups(uncategorized))] : [])
  end

  def self.product_groups(entries)
    entries.group_by(&:product).map do |product, product_entries|
      plain, filtered = product_entries.partition { it.filter.nil? }
      filters = filtered.group_by(&:filter).map do |filter, filter_entries|
        FilterGroup.new(name: filter.invoice_name, filter:, entries: by_period(filter_entries))
      end

      ProductGroup.new(name: product.invoice_name, product:, entries: product_entries, unfiltered_entries: by_period(plain), filters: sort_by_name(filters))
    end.then { sort_by_name(it) }
  end

  def self.total(entries)
    entries.sum(&:amount_cents)
  end

  def self.by_period(entries)
    entries.sort_by do |entry|
      fee = entry.fee
      parent = fee.true_up_parent_fee || fee
      [parent.properties["from_datetime"].to_s, parent.id, fee.true_up_parent_fee_id ? 1 : 0]
    end
  end

  def self.sort_by_name(items)
    items.sort_by { it.name.downcase }
  end

  def self.contract_name(contract)
    contract.name.presence || contract.catalog_plan&.invoice_display_name.presence || contract.catalog_plan&.name
  end

  private_class_method :sections, :product_groups, :by_period, :sort_by_name, :contract_name
end
