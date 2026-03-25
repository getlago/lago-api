# frozen_string_literal: true

module RateSchedules
  class OrganizationBillingService < BaseService
    Result = BaseResult

    def initialize(organization:, billing_at: Time.current)
      @organization = organization
      @billing_at = billing_at

      super
    end

    def call
      billable_subscription_rate_schedules
        .group_by { |srs| srs.subscription.customer_id }
        .each_value do |customer_srs|
          BillRateSchedulesJob.perform_later(customer_srs.map(&:id), billing_at.to_i)
        end

      result
    end

    private

    attr_reader :organization, :billing_at

    def billable_subscription_rate_schedules
      organization.subscription_rate_schedules
        .active
        .where(next_billing_date: ...billing_at.to_date)
        .includes(:subscription)
    end
  end
end
