# frozen_string_literal: true

module Metadata
  # Remove a key from an existing metadata.
  # Return an error result if the metadata has already been deleted.
  class DeleteItemKeyService < BaseService
    use Middlewares::Yabeda::DurationMiddleware

    Result = BaseResult[:item, :key, :deleted_value, :changed]

    # @option [Metadata::MetadataItem] :item The metadata item to modify
    # @option [#to_s] :key The key of the metadata item to delete
    def initialize(item, key:)
      super()

      result.item = item
      result.key = key
      result.changed = false
    end

    def call
      old_value = item.value.to_h
      key = result.key.to_s

      result.changed = old_value.key?(key)
      result.deleted_value = old_value[key]
      item.update!(value: old_value.except(key))

      result
    rescue ActiveRecord::RecordNotFound
      result.not_found_failure!(resource: "metadata_item")
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    delegate :item, to: :result
  end
end
