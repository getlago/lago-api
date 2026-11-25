# frozen_string_literal: true

module CopyToProduction
  module Items
    class FeatureItem < BaseItem
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
    end
  end
end
