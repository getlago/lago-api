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

      private

      def resource_name
        "feature"
      end
    end
  end
end
