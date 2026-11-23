# frozen_string_literal: true

module BillingEngineMigrations
  class CopySubscriptionService < BaseService
    Result = BaseResult[:contract]

    def initialize(migration:, subscription:)
      @migration = migration
      @subscription = subscription
      super
    end

    def call
      return result unless migration.shadowing?
      return result unless subscription.organization_id == migration.organization_id
      return result unless subscription.active?
      return result unless migration.plan_mapping.key?(subscription.plan.code)

      if subscription.plan.parent_id.present?
        log(:info, "skipped: plan_override_not_supported")
        return result
      end

      return result if subscription.ending_at&.past?
      return result if shadow_organization.contracts.live.exists?(external_id: subscription.external_id)

      customer_result = CopyCustomerService.call(migration:, customer: subscription.customer)
      if customer_result.failure?
        log(:warn, "cannot create customer: #{customer_result.error.message}")
        return result.fail_with_error!(customer_result.error)
      end

      contract_result = Contracts::CreateService.call(
        organization: shadow_organization,
        params: contract_params(customer_result.customer)
      )
      return result if contract_result.failure? && already_copied?(contract_result.error)

      if contract_result.failure?
        log(:warn, "cannot create contract: #{contract_result.error.message}")
        return result.fail_with_error!(contract_result.error)
      end

      result.contract = contract_result.contract
      result
    end

    private

    attr_reader :migration, :subscription

    delegate :shadow_organization, to: :migration

    def already_copied?(error)
      return false unless error.is_a?(BaseService::ValidationFailure)

      error.messages[:external_id]&.include?("value_already_exists") ||
        error.messages[:code]&.include?("value_already_exist")
    end

    def contract_params(shadow_customer)
      {
        external_customer_id: shadow_customer.external_id,
        external_id: subscription.external_id,
        code: subscription.id,
        name: subscription.name,
        plan_code: migration.plan_mapping.fetch(subscription.plan.code),
        billing_time: subscription.billing_time,
        started_at: subscription.started_at&.iso8601(6),
        billing_anchor_date:,
        ended_at: subscription.ending_at&.iso8601(6)
      }.compact_blank
    end

    # V2 periods are cut from the anchor only (billing_time is not read), so a calendar
    # subscription is anchored on a calendar boundary: Monday for weekly plans, Jan 1 otherwise.
    def billing_anchor_date
      timezone = subscription.customer.applicable_timezone

      if subscription.anniversary?
        subscription.subscription_at&.in_time_zone(timezone)&.to_date&.iso8601
      else
        start_date = subscription.started_at&.in_time_zone(timezone)&.to_date
        calendar_anchor(start_date)&.iso8601
      end
    end

    def calendar_anchor(start_date)
      return if start_date.nil?

      subscription.plan.weekly? ? start_date.beginning_of_week(:monday) : start_date.beginning_of_year
    end

    def log(level, message)
      Rails.logger.public_send(
        level,
        "BillingEngineMigrations::CopySubscriptionService: subscription #{subscription.external_id} " \
        "(migration #{migration.id}): #{message}"
      )
    end
  end
end
