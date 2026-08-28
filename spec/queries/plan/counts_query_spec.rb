# frozen_string_literal: true

require "rails_helper"

RSpec.describe Plan::CountsQuery do
  subject(:plans) { described_class.call(organization:, filters: {plan_ids:}).plans }

  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:empty_plan) { create(:plan, organization:) }
  let(:child_plan) { create(:plan, organization:, parent: plan) }
  let(:other_plan) { create(:plan) }
  let(:plan_ids) { [plan.id, empty_plan.id, other_plan.id] }

  let(:customer) { create(:customer, organization:) }
  let(:child_customer) { create(:customer, organization:) }
  let(:pending_customer) { create(:customer, organization:) }

  let(:direct_subscription1) { create(:subscription, customer:, plan:, organization:) }
  let(:direct_subscription2) { create(:subscription, customer:, plan:, organization:) }
  let(:pending_subscription) { create(:subscription, :pending, customer: pending_customer, plan:, organization:) }
  let(:child_subscription1) { create(:subscription, customer:, plan: child_plan, organization:) }
  let(:child_subscription2) { create(:subscription, customer: child_customer, plan: child_plan, organization:) }
  let(:terminated_child_subscription) { create(:subscription, :terminated, customer: child_customer, plan: child_plan, organization:) }

  before do
    billable_metric = create(:billable_metric, organization:)
    add_on = create(:add_on, organization:)

    create_list(:standard_charge, 2, plan:, organization:, billable_metric:)
    create(:standard_charge, plan:, organization:, billable_metric:, deleted_at: Time.current)
    create(:fixed_charge, plan:, organization:, add_on:)
    create(:fixed_charge, :deleted, plan:, organization:, add_on:)

    shared_invoice = create(:invoice, :draft, customer:, organization:)
    create(:invoice_subscription, invoice: shared_invoice, subscription: direct_subscription1, organization:)
    create(:invoice_subscription, invoice: shared_invoice, subscription: direct_subscription2, organization:)
    create(:invoice_subscription, invoice: shared_invoice, subscription: child_subscription1, organization:)
    create(:invoice_subscription, invoice: shared_invoice, subscription: child_subscription2, organization:)

    finalized_invoice = create(:invoice, customer:, organization:)
    create(:invoice_subscription, invoice: finalized_invoice, subscription: direct_subscription1, organization:)

    pending_subscription
    terminated_child_subscription
  end

  it "returns all counts and deduplicates customers and invoices across the plan hierarchy" do
    expect(plans).to eq({
      plan.id => {
        active_subscriptions_count: 4,
        charges_count: 2,
        customers_count: 2,
        draft_invoices_count: 1,
        fixed_charges_count: 1,
        subscriptions_count: 6
      },
      empty_plan.id => {
        active_subscriptions_count: 0,
        charges_count: 0,
        customers_count: 0,
        draft_invoices_count: 0,
        fixed_charges_count: 0,
        subscriptions_count: 0
      }
    })
  end
end
