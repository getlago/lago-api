# frozen_string_literal: true

module CatalogWalletSelectors
  class ReplaceService < BaseService
    Result = BaseResult[:selectors]

    TARGET_COLUMNS = %i[selector_type fee_type product_category_id product_id product_filter_id].freeze

    def initialize(wallet:, applies_to:)
      @wallet = wallet
      @applies_to = applies_to
      super
    end

    def call
      return result.not_found_failure!(resource: "wallet") unless wallet

      targets = resolve_targets

      ActiveRecord::Base.transaction do
        existing = wallet.selectors.index_by { |selector| selector.attributes.symbolize_keys.slice(*TARGET_COLUMNS) }
        existing.except(*targets.keys).each_value(&:destroy!)

        targets.each do |target, with_product_filters|
          selector = existing[target] || wallet.selectors.new(organization:, **target)
          selector.update!(with_product_filters:)
        end
      end

      wallet.selectors.reset
      result.selectors = wallet.selectors
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      e.result
    end

    private

    attr_reader :wallet, :applies_to, :entries

    delegate :organization, to: :wallet

    def resolve_targets
      refuse!(:applies_to, "value_is_invalid") unless applies_to.nil? || applies_to.is_a?(Hash)

      scope = (applies_to || {}).with_indifferent_access
      refuse!(:"applies_to.exclude", "not_supported") if scope.key?(:exclude)

      @entries = scope[:include] || []
      refuse!(:"applies_to.include", "value_is_invalid") unless entries.is_a?(Array)

      entries.each_with_index.with_object({}) do |(entry, index), targets|
        target, with_product_filters = resolve_entry(entry, index)
        targets[target] ||= with_product_filters
      end
    end

    def resolve_entry(entry, index)
      refuse_entry!(index, :base, "value_is_invalid") unless entry.is_a?(Hash)

      entry = entry.with_indifferent_access
      type = entry[:type]
      unless CatalogWalletSelector.selector_types.key?(type)
        refuse_entry!(index, :type, "value_is_invalid", allowed_values: CatalogWalletSelector.selector_types.keys)
      end
      refuse_entry!(index, :code, "value_is_mandatory") if entry[:code].blank?
      refuse_entry!(index, :code, "value_is_invalid") unless entry[:code].is_a?(String)

      # Only a product selector can reach its filters; elsewhere the flag may only be off.
      with_product_filters = entry[:with_product_filters]
      allowed_flags = (type == "product") ? [nil, true, false] : [nil, false]
      refuse_entry!(index, :with_product_filters, "value_is_invalid") unless allowed_flags.include?(with_product_filters)

      target = TARGET_COLUMNS.index_with(nil).merge(selector_type: type, **send(:"#{type}_target", entry, index))
      [target, with_product_filters == true]
    end

    def fee_type_target(entry, index)
      unless CatalogWalletSelector.fee_types.key?(entry[:code])
        refuse_entry!(index, :code, "value_is_invalid", allowed_values: CatalogWalletSelector.fee_types.keys)
      end

      {fee_type: entry[:code]}
    end

    def product_category_target(entry, index)
      product_category = product_categories_by_code[entry[:code]]
      refuse_entry!(index, :code, "product_category_not_found") unless product_category

      {product_category_id: product_category.id}
    end

    def product_target(entry, index)
      product = products_by_code[entry[:code]]
      refuse_entry!(index, :code, "product_not_found") unless product

      {product_id: product.id}
    end

    # A filter code is unique inside its product only, so the entry names the product too.
    def product_filters_target(entry, index)
      refuse_entry!(index, :product_code, "value_is_mandatory") if entry[:product_code].blank?

      product = products_by_code[entry[:product_code].to_s]
      refuse_entry!(index, :product_code, "product_not_found") unless product

      product_filter = product_filters_by_target[[product.id, entry[:code]]]
      refuse_entry!(index, :code, "product_filter_not_found") unless product_filter

      {product_filter_id: product_filter.id}
    end

    # One query per kind of record, whatever the number of entries.
    def product_categories_by_code
      @product_categories_by_code ||= organization.product_categories
        .where(code: codes_of("product_category", :code))
        .index_by(&:code)
    end

    def products_by_code
      @products_by_code ||= organization.products
        .where(code: codes_of("product", :code) + codes_of("product_filters", :product_code))
        .index_by(&:code)
    end

    def product_filters_by_target
      @product_filters_by_target ||= organization.product_filters
        .where(product_id: products_by_code.values.map(&:id), code: codes_of("product_filters", :code))
        .index_by { [it.product_id, it.code] }
    end

    def codes_of(type, key)
      entries.filter_map do |entry|
        next unless entry.is_a?(Hash)

        entry = entry.with_indifferent_access
        entry[key].to_s if entry[:type] == type && !entry[key].is_a?(Enumerable)
      end
    end

    def refuse_entry!(index, field, error_code, **meta)
      refuse!(ValidationFailure.item_field("applies_to.include", index, field), error_code, **meta)
    end

    def refuse!(field, error_code, **meta)
      result.single_validation_failure!(field:, error_code:, meta:).raise_if_error!
    end
  end
end
