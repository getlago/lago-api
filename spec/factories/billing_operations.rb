# frozen_string_literal: true

FactoryBot.define do
  factory :billing_operation do
    organization
    contract_rate_card do
      customer = association(:customer, organization:)
      association(:contract_rate_card, organization:, contract: association(:contract, organization:, customer:))
    end
    customer { contract_rate_card.contract.customer }
    action_type { "renew_fixed_advance" }
    reason { :contract_activation }
    billing_at { Time.current }
    target_cycle_started_at { Time.current.beginning_of_month }
    coverage_started_at { target_cycle_started_at }
    coverage_ended_at { coverage_started_at&.+(1.month) }

    trait :with_plan do
      to_create do |operation|
        card = operation.contract_rate_card
        schedule = Billing::RateCards::BuildScheduleService.call!(contract_rate_card: card).schedule
        obligation = schedule.obligation_at(operation.coverage_started_at)
        planned = BillingOperations::Schedule::PlannedOperation.from_obligation(obligation)
        raise "No obligation for billing operation fixture" unless planned

        planned = planned.with(billing_at: operation.billing_at)
        saved = BillingOperations::CreateService.call!(
          contract_rate_card: card, action_type: operation.action_type, reason: operation.reason, planned_operation: planned
        ).operation
        saved.update!(
          invoice: operation.invoice, processed_at: operation.processed_at,
          cancelled_at: operation.cancelled_at, cancellation_reason: operation.cancellation_reason
        )
        operation.id = saved.id
        operation.reload
      end
    end
  end
end
