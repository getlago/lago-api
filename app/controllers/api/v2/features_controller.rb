# frozen_string_literal: true

module Api
  module V2
    class FeaturesController < BaseController
      cursor_paginated_index(::Entitlement::Feature)
      date_range_filtered_index(:created_at)
      serializable_with ::V2::Entitlement::FeatureSerializer

      def index
        result = ::Entitlement::FeaturesQuery.call(
          organization: current_organization,
          pagination: cursor,
          search_term: params[:search_term],
          filters: date_range_filters
        )

        if result.success?
          render_features(result.features)
        else
          render_error_response(result)
        end
      end

      def create
        # v2 creates privileges on their own endpoint, so even an empty or null list is refused.
        if feature_payload.key?(:privileges)
          return invalid_request_error(code: "parameter_not_allowed", error_details: {"feature.privileges" => {}})
        end

        result = ::Entitlement::FeatureCreateService.call(
          organization: current_organization,
          params: feature_payload.permit(:code, :name, :description).to_h.symbolize_keys
        )

        if result.success?
          render_feature(result.feature)
        else
          render_error_response(result)
        end
      end

      private

      def feature_payload
        @feature_payload ||= begin
          payload = params.require(:feature)
          unless payload.is_a?(ActionController::Parameters)
            raise ActionController::ParameterMissing, :feature
          end

          payload
        end
      end

      def resource_name
        "feature"
      end
    end
  end
end
