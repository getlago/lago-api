# frozen_string_literal: true

module CatalogWalletSelectors
  class ReplaceService < BaseService
    Result = BaseResult[:selectors]

    Entry = Data.define(:index, :type, :code, :product_code, :with_product_filters)

    TARGET_COLUMNS = %i[selector_type fee_type product_category_id product_id product_filter_id].freeze

    def initialize(wallet:, applies_to:)
      @wallet = wallet
      @applies_to = applies_to
      super
    end

    def call
      return result.not_found_failure!(resource: "wallet") unless wallet

      @entries = parse_entries
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

    def parse_entries
      refuse!(:applies_to, "value_is_invalid") unless applies_to.nil? || applies_to.is_a?(Hash)

      scope = applies_to.to_h.with_indifferent_access
      refuse!(:"applies_to.exclude", "not_supported") if scope.key?(:exclude)

      list = scope[:include] || []
      refuse!(:"applies_to.include", "value_is_invalid") unless list.is_a?(Array)

      list.each_with_index.map { |raw, index| parse_entry(raw, index) }
    end

    def parse_entry(raw, index)
      refuse_entry!(index, :base, "value_is_invalid") unless raw.is_a?(Hash)

      raw = raw.with_indifferent_access
      type, code, product_code, flag = raw.values_at(:type, :code, :product_code, :with_product_filters)

      selector_types = CatalogWalletSelector.selector_types.keys
      refuse_entry!(index, :type, "value_is_invalid", allowed_values: selector_types) unless selector_types.include?(type)
      refuse_unless_string!(index, :code, code)

      # Only a product selector can reach its filters; elsewhere the flag may only be off.
      allowed_flags = (type == "product") ? [nil, true, false] : [nil, false]
      refuse_entry!(index, :with_product_filters, "value_is_invalid") unless allowed_flags.include?(flag)

      fee_types = CatalogWalletSelector.fee_types.keys
      if type == "fee_type" && !fee_types.include?(code)
        refuse_entry!(index, :code, "value_is_invalid", allowed_values: fee_types)
      end
      refuse_unless_string!(index, :product_code, product_code) if type == "product_filters"

      Entry.new(index:, type:, code:, product_code:, with_product_filters: flag == true)
    end

    def resolve_targets
      entries.each_with_object({}) do |entry, targets|
        target = TARGET_COLUMNS.index_with(nil).merge(selector_type: entry.type, **target_columns(entry))
        targets[target] = targets.fetch(target, false) || entry.with_product_filters
      end
    end

    def target_columns(entry)
      case entry.type
      when "fee_type"
        {fee_type: entry.code}
      when "product_category"
        product_category_id = category_ids[entry.code]
        refuse_entry!(entry.index, :code, "product_category_not_found") unless product_category_id

        {product_category_id:}
      when "product"
        product_id = product_ids[entry.code]
        refuse_entry!(entry.index, :code, "product_not_found") unless product_id

        {product_id:}
      when "product_filters"
        product_id = product_ids[entry.product_code]
        refuse_entry!(entry.index, :product_code, "product_not_found") unless product_id

        product_filter_id = filter_ids[[product_id, entry.code]]
        refuse_entry!(entry.index, :code, "product_filter_not_found") unless product_filter_id

        {product_filter_id:}
      end
    end

    def category_ids
      @category_ids ||= organization.product_categories
        .where(code: entries_of("product_category").map(&:code))
        .pluck(:code, :id).to_h
    end

    def product_ids
      @product_ids ||= organization.products
        .where(code: entries_of("product").map(&:code) + entries_of("product_filters").map(&:product_code))
        .pluck(:code, :id).to_h
    end

    # A filter code is unique inside its product only.
    def filter_ids
      @filter_ids ||= organization.product_filters
        .where(product_id: product_ids.values, code: entries_of("product_filters").map(&:code))
        .pluck(:product_id, :code, :id)
        .to_h { |product_id, code, id| [[product_id, code], id] }
    end

    def entries_of(type)
      entries.select { it.type == type }
    end

    def refuse_unless_string!(index, field, value)
      refuse_entry!(index, field, "value_is_mandatory") if value.blank?
      refuse_entry!(index, field, "value_is_invalid") unless value.is_a?(String)
    end

    def refuse_entry!(index, field, error_code, **meta)
      refuse!(ValidationFailure.item_field("applies_to.include", index, field), error_code, **meta)
    end

    def refuse!(field, error_code, **meta)
      result.single_validation_failure!(field:, error_code:, meta:).raise_if_error!
    end
  end
end
