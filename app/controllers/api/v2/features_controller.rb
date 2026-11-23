# frozen_string_literal: true

module Api
  module V2
    class FeaturesController < BaseController
      cursor_paginated_index(::Entitlement::Feature)
      date_range_filtered_index(:created_at)
      serializable_with ::V2::Entitlement::FeatureSerializer

      def show
        feature = current_organization.features.find_by(code: params[:code])

        return not_found_error(resource: "feature") unless feature

        render_feature(feature)
      end

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
        attributes = params.expect(feature: [:code, :name, :description])

        result = ::Entitlement::FeatureCreateService.call(
          organization: current_organization,
          params: attributes.to_h.symbolize_keys
        )

        if result.success?
          render_feature(result.feature)
        else
          render_error_response(result)
        end
      end

      def update
        attributes = params.expect(feature: [:name, :description])

        result = ::Entitlement::FeatureUpdateService.call(
          # The service answers not found for an unknown or discarded code.
          feature: current_organization.features.find_by(code: params[:code]),
          params: attributes.to_h.symbolize_keys,
          # PUT included: with partial: false the service discards every privilege missing from the params.
          partial: true
        )

        if result.success?
          render_feature(result.feature)
        else
          render_error_response(result)
        end
      end

      def destroy
        feature = current_organization.features.find_by(code: params[:code])
        result = ::Entitlement::FeatureDestroyService.call(feature:)

        if result.success?
          render_feature(result.feature)
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
