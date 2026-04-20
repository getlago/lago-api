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
        .group_by { |srs| srs.subscription.customer }
        .each do |customer, customer_srs|
          BillRateSchedulesJob.perform_later(customer, customer_srs.map(&:id), billing_at.to_i)
        end

      result
    end

    private

    attr_reader :organization, :billing_at

    # NOTE: SubscriptionRateSchedules eligible to be billed now:
    # - next_billing_date is set (nil means nothing more to bill)
    # - next_billing_date has been reached (in the customer/billing entity TZ)
    def billable_subscription_rate_schedules
      organization.subscription_rate_schedules
        .joins(subscription: {customer: :billing_entity})
        .where.not(next_billing_date: nil)
        .where(<<~SQL.squish, billing_at:)
          subscription_rate_schedules.next_billing_date = DATE((:billing_at)#{at_time_zone})
        SQL
        .includes(subscription: :customer)
    end
  end
end
