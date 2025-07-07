# frozen_string_literal: true

module Entitlement
  class FeaturePartialUpdateService < FeatureBaseUpdateService
    def call
      handle_validation_and_webhooks do
        ActiveRecord::Base.transaction do
          update_feature_attributes
          update_privileges if params[:privileges].present?

          feature.save!
        end
      end
    end
  end
end
