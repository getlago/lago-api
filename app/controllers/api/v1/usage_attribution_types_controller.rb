# frozen_string_literal: true

module Api
  module V1
    class UsageAttributionTypesController < Api::BaseController
      before_action :ensure_feature_flag!

      def create
        parent_attributes = parent_attributes_from(input_params)
        return not_found_error(resource: "parent_usage_attribution_type") unless parent_attributes

        result = ::UsageAttributionTypes::CreateService.call(
          organization: current_organization,
          params: input_params.except(:parent_code).merge(parent_attributes)
        )

        if result.success?
          render_usage_attribution_type(result.usage_attribution_type)
        else
          render_error_response(result)
        end
      end

      def update
        usage_attribution_type = find_usage_attribution_type
        return not_found_error(resource: "usage_attribution_type") unless usage_attribution_type

        parent_attributes = parent_attributes_from(input_params)
        return not_found_error(resource: "parent_usage_attribution_type") unless parent_attributes

        result = ::UsageAttributionTypes::UpdateService.call(
          usage_attribution_type:,
          params: input_params.except(:parent_code).merge(parent_attributes)
        )

        if result.success?
          render_usage_attribution_type(result.usage_attribution_type)
        else
          render_error_response(result)
        end
      end

      def destroy
        result = ::UsageAttributionTypes::DestroyService.call(
          usage_attribution_type: find_usage_attribution_type
        )

        if result.success?
          render_usage_attribution_type(result.usage_attribution_type)
        else
          render_error_response(result)
        end
      end

      def show
        usage_attribution_type = find_usage_attribution_type
        return not_found_error(resource: "usage_attribution_type") unless usage_attribution_type

        render_usage_attribution_type(usage_attribution_type)
      end

      def index
        result = ::UsageAttributionTypesQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters: {role: params[:role]},
          search_term: params[:search_term]
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.usage_attribution_types,
              ::V1::UsageAttributionTypeSerializer,
              collection_name: "usage_attribution_types",
              meta: pagination_metadata(result.usage_attribution_types)
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      def find_usage_attribution_type
        current_organization.usage_attribution_types.find_by(code: params[:code])
      end

      def parent_attributes_from(permitted_params)
        return {} unless permitted_params.key?(:parent_code)

        parent_code = permitted_params[:parent_code]
        return {parent_id: nil} if parent_code.blank?

        parent = current_organization.usage_attribution_types.find_by(code: parent_code)
        {parent_id: parent.id} if parent
      end

      def input_params
        @input_params ||= params.require(:usage_attribution_type)
          .permit(:code, :name, :role, :parent_code, attribution_keys: [])
      end

      def render_usage_attribution_type(usage_attribution_type)
        render(
          json: ::V1::UsageAttributionTypeSerializer.new(
            usage_attribution_type,
            root_name: "usage_attribution_type"
          )
        )
      end

      def ensure_feature_flag!
        forbidden_error(code: "feature_unavailable") unless current_organization.account_tree_enabled?
      end

      def resource_name
        "usage_attribution_type"
      end
    end
  end
end
