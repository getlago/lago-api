# frozen_string_literal: true

module Api
  module V2
    module Plans
      class MetadataController < Api::V2::BaseController
        serializable_with ::V1::MetadataSerializer, root: :metadata, expand_on: []

        before_action :find_catalog_plan

        def create
          return invalid_metadata_request unless valid_metadata?

          update_metadata(params: {metadata:})
        end

        def update
          return invalid_metadata_request unless valid_metadata?

          update_metadata(params: {metadata:}, partial_metadata: true)
        end

        def destroy
          update_metadata(params: {metadata: nil})
        end

        def destroy_key
          update_metadata(params: {}, delete_metadata_key: params[:key])
        end

        private

        attr_reader :catalog_plan

        def find_catalog_plan
          @catalog_plan = current_organization.catalog_plans.find_by(code: params[:plan_code])
          not_found_error(resource: "plan") unless @catalog_plan
        end

        def update_metadata(**options)
          result = ::CatalogPlans::UpdateService.call(catalog_plan:, **options)
          result.success? ? render_resource(catalog_plan.reload.metadata) : render_error_response(result)
        end

        def metadata
          value = metadata_params
          value.is_a?(ActionController::Parameters) ? value.permit!.to_h : value.to_h
        end

        def metadata_params
          params.fetch(:metadata, {})
        end

        def valid_metadata?
          metadata_params.is_a?(ActionController::Parameters) || metadata_params.is_a?(Hash)
        end

        def invalid_metadata_request
          details = {reason: "value_is_invalid"}
          details[:value] = metadata_params if metadata_params.is_a?(String)

          invalid_request_error(
            code: "value_is_invalid",
            error_details: {metadata: details}
          )
        end

        def resource_name
          "plan"
        end
      end
    end
  end
end
