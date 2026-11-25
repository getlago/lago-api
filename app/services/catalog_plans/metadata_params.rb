# frozen_string_literal: true

module CatalogPlans
  module MetadataParams
    private

    def malformed_metadata?(metadata)
      !metadata.nil? && !metadata.is_a?(Hash)
    end

    # The metadata record names its errors in sentences, on its own `value` column.
    def replace_metadata!(catalog_plan, metadata)
      unless Metadata::UpdateItemService.call(owner: catalog_plan, value: metadata&.transform_keys(&:to_s)).success?
        result.single_validation_failure!(field: :metadata, error_code: "value_is_invalid").raise_if_error!
      end
    end
  end
end
