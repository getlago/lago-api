# frozen_string_literal: true

module CopyToProduction
  module Items
    class FeatureItem < BaseItem
      def find_source(id)
        sandbox.features.find_by(id:)
      end

      def find_existing(source)
        production.features.find_by(code: source.code)
      end

      def copy!(source, _resolved)
        Entitlement::FeatureCreateService.call!(
          organization: production,
          params: {
            code: source.code,
            name: source.name,
            description: source.description,
            privileges: source.privileges.order(:created_at, :id).map do |privilege|
              privilege.slice(:code, :name, :value_type, :config).symbolize_keys
            end
          }
        ).feature
      end

      def unique_indexes
        {"idx_features_code_unique_per_organization" => :code}
      end
    end
  end
end
