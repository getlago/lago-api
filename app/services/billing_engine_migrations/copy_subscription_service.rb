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
      return result unless in_scope?

      return skip("plan_override_not_supported") if plan_override?
      return result if already_ended? || already_copied?
      return skip("external_id_taken_by_other_subscription") if external_id_taken?

      customer_result = CopyCustomerService.call(migration:, customer: subscription.customer)
      return fail_with(customer_result, "cannot create customer") if customer_result.failure?

      create_contract(customer_result.customer)
      result
    end

    private

    attr_reader :migration, :subscription

    delegate :shadow_organization, to: :migration

    def in_scope?
      migration.shadowing? &&
        subscription.organization_id == migration.organization_id &&
        subscription.active? &&
        migration.plan_mapping.key?(subscription.plan.code)
    end

    def plan_override?
      subscription.plan.parent_id.present?
    end

    def already_ended?
      subscription.ending_at&.past?
    end

    def already_copied?
      live_contract_code == subscription.id
    end

    def external_id_taken?
      !live_contract_code.nil? && !already_copied?
    end

    def live_contract_code
      return @live_contract_code if defined?(@live_contract_code)

      @live_contract_code = shadow_organization.contracts.live.where(external_id: subscription.external_id).pick(:code)
    end

    def create_contract(shadow_customer)
      contract_result = Contracts::CreateService.call(
        organization: shadow_organization,
        params: contract_params(shadow_customer)
      )

      if contract_result.success?
        result.contract = contract_result.contract
      elsif !copied_concurrently?(contract_result.error)
        fail_with(contract_result, "cannot create contract")
      end
    end

    def copied_concurrently?(error)
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
        billing_anchor_date: billing_anchor_date&.iso8601,
        ended_at: subscription.ending_at&.iso8601(6)
      }.compact_blank
    end

    # V2 cuts periods from the anchor only and never reads billing_time, so a calendar
    # subscription is anchored on a calendar boundary to keep the V1 periods.
    def billing_anchor_date
      if subscription.anniversary?
        date_in_customer_timezone(subscription.subscription_at)
      else
        calendar_boundary(date_in_customer_timezone(subscription.started_at))
      end
    end

    def calendar_boundary(date)
      return if date.nil?

      subscription.plan.weekly? ? date.beginning_of_week(:monday) : date.beginning_of_year
    end

    def date_in_customer_timezone(time)
      time&.in_time_zone(subscription.customer.applicable_timezone)&.to_date
    end

    def skip(reason)
      log(:info, "skipped: #{reason}")
      result
    end

    def fail_with(inner_result, message)
      log(:warn, "#{message}: #{inner_result.error.message}")
      result.fail_with_error!(inner_result.error)
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
