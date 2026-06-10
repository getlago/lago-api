# frozen_string_literal: true

module Mutations
  module ProductItems
    # The billable metric and product are supplied by id on the GraphQL API, so a
    # validation error about either must name the id field the caller sent — not
    # the neutral association name the shared service/model emits.
    module SurfaceErrorFields
      extend ActiveSupport::Concern

      FIELD_MAP = {billable_metric: :billable_metric_id, product: :product_id}.freeze

      private

      def render_item_error(result)
        if result.error.is_a?(BaseService::ValidationFailure)
          messages = result.error.messages.transform_keys { |key| FIELD_MAP[key.to_sym] || key }
          return validation_error(messages:)
        end

        result_error(result)
      end
    end
  end
end
