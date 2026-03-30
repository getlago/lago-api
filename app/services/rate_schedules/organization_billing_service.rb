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
        .joins(subscription: {customer: :billing_entity})
        .joins(:cycles)
        .where(<<~SQL.squish, billing_at:)
          DATE(subscription_rate_schedule_cycles.to_datetime) <= DATE((:billing_at)#{at_time_zone})
        SQL
        .where(<<~SQL.squish)
          NOT EXISTS (
            SELECT 1 FROM fees
            WHERE fees.subscription_rate_schedule_cycle_id = subscription_rate_schedule_cycles.id
          )
        SQL
        .includes(subscription: :customer)
        .distinct
    end
  end
end
