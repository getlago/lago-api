# frozen_string_literal: true

module Subscriptions
  module BillingPeriods
    class BackfillOrganizationJob < ApplicationJob
      queue_as :low_priority

      unique :until_executed, on_conflict: :log

      def perform(organization)
        Subscriptions::BillingPeriods::BackfillOrganizationService.call!(organization:)
      end
    end
  end
end
