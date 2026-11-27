# frozen_string_literal: true

module CopyToProduction
  module Items
    class FeatureItem < BaseItem
      ATTRIBUTES = %i[code name description].freeze
      PRIVILEGE_ATTRIBUTES = %i[code name value_type config].freeze

      def copy!(source, _resolved)
        Entitlement::FeatureCreateService.call!(
          organization: production,
          params: source.slice(*ATTRIBUTES).symbolize_keys.merge(
            privileges: source.privileges.order(:created_at, :id).map do |privilege|
              privilege.slice(*PRIVILEGE_ATTRIBUTES).symbolize_keys
            end
          )
        ).feature
      end
    end
  end
end
