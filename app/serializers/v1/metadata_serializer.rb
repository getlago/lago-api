# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module V1
  class MetadataSerializer < ModelSerializer
    def serialize
      model&.value
    end
  end
end
