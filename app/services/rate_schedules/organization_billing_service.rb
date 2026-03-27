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
        .joins(subscription: {customer: :billing_entity})
        .where("subscription_rate_schedules.next_billing_date <= DATE((:billing_at)#{at_time_zone})", billing_at:)
        .where("subscription_rate_schedules.intervals_to_bill IS NULL " \
          "OR subscription_rate_schedules.intervals_billed < subscription_rate_schedules.intervals_to_bill")
        .includes(subscription: :customer)
    end
  end
end
