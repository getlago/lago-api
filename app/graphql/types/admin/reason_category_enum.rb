# frozen_string_literal: true

module Types
  module Admin
    class ReasonCategoryEnum < Types::BaseEnum
      graphql_name "AdminReasonCategory"
      description "Reason category for a premium integration toggle"

      ::Admin::PremiumIntegrations::ToggleService::REASON_CATEGORIES.each do |category|
        value category, description: category.to_s.humanize
      end
    end
  end
end
