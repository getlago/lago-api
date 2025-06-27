# frozen_string_literal: true

module Api
  module V1
    class FeaturesController < Api::BaseController
      def index
        result = FeaturesQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          }
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.features.includes(:privileges),
              ::V1::Entitlement::FeatureSerializer,
              collection_name: "features",
              meta: pagination_metadata(result.features)
            )
          )
        else
          render_error_response(result)
        end
      end

      def show
        feature = current_organization.features.where(code: params[:code]).first

        return not_found_error(resource: "feature") unless feature

        render(
          json: ::V1::Entitlement::FeatureSerializer.new(
            feature,
            root_name: "feature"
          )
        )
      end

      def destroy
        feature = current_organization.features.where(code: params[:code]).first
        result = ::Entitlement::FeatureDestroyService.call(feature:)

        if result.success?
          render(
            json: ::V1::Entitlement::FeatureSerializer.new(
              result.feature,
              root_name: "feature"
            )
          )
        else
          render_error_response(result)
        end
      end

      def destroy_privilege
        feature = current_organization.features.where(code: params[:code]).first
        return not_found_error(resource: "feature") unless feature

        privilege = feature.privileges.where(code: params[:privilege_code]).first
        return not_found_error(resource: "privilege") unless privilege

        result = ::Entitlement::PrivilegeDestroyService.call(privilege:)

        if result.success?
          render(
            json: ::V1::Entitlement::FeatureSerializer.new(
              feature,
              root_name: "feature"
            )
          )
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
