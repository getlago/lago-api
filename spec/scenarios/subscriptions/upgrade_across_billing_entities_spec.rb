# frozen_string_literal: true

require "rails_helper"

describe "Subscription Upgrade Across Billing Entities Scenario", transaction: false do
  let(:organization) do
    create(:organization, webhook_url: false, email_settings: [], billing_entities: [us_entity, eu_entity])
  end

  let(:us_entity) do
    create(:billing_entity, document_numbering: "per_customer", document_number_prefix: "BEUS")
  end

  let(:eu_entity) do
    create(:billing_entity, document_numbering: "per_customer", document_number_prefix: "BEEU")
  end

  let(:customer) { create(:customer, organization:, billing_entity: us_entity) }

  let(:billable_metric) { create(:sum_billable_metric, organization:, code: "api_calls") }

  let(:monthly_plan) do
    create(:plan, organization:, interval: "monthly", amount_cents: 1000, pay_in_advance: true)
  end

  let(:downgrade_plan) do
    create(:plan, organization:, interval: "monthly", amount_cents: 500, pay_in_advance: true)
  end

  let(:yearly_plan) do
    create(:plan, organization:, interval: "yearly", amount_cents: 12_000, pay_in_advance: true)
  end

  let(:subscription_at) { DateTime.new(2024, 6, 5, 10, 0) }
  let(:upgrade_at) { DateTime.new(2024, 6, 20, 10, 0) }
  let(:subscription_billing_entity_code) { eu_entity.code }

  def change_plan(plan, params = {})
    create_subscription(
      {
        external_customer_id: customer.external_id,
        external_id: customer.external_id,
        plan_code: plan.code,
        billing_time: "anniversary"
      }.merge(params)
    )
  end

  def send_api_calls(units)
    create_event(
      {
        code: billable_metric.code,
        external_subscription_id: customer.external_id,
        properties: {item_id: units}
      }
    )
  end

  def expect_invoices_billed_on_their_own_entity
    # NOTE: no invoice ever mixes subscriptions from different billing entities
    customer.invoices.find_each do |invoice|
      expect(invoice.subscriptions.map(&:applicable_billing_entity_id).uniq).to eq([invoice.billing_entity_id])
    end
  end

  def expect_no_failed_invoice
    expect(customer.invoices.where(status: %i[failed generating])).to be_empty
    expect(ErrorDetail.invoice_generation_error).to be_empty
  end

  before do
    # NOTE: 1 API call costs 1 EUR, billed in arrears
    create(:standard_charge, plan: monthly_plan, billable_metric:, properties: {amount: "1"})

    travel_to(subscription_at) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: monthly_plan.code,
          billing_time: "anniversary",
          subscription_at: subscription_at.iso8601,
          billing_entity_code: subscription_billing_entity_code
        }.compact
      )
    end

    travel_to(DateTime.new(2024, 6, 12, 10, 0)) { send_api_calls(5) }
  end

  context "when the upgrade moves the subscription to the customer's billing entity" do
    it "bills the terminated and the upgraded subscription on their own billing entity's invoice" do
      subscription = customer.subscriptions.sole
      expect(subscription.billing_entity_id).to eq(eu_entity.id)

      initial_invoice = subscription.invoices.sole
      expect(initial_invoice.billing_entity_id).to eq(eu_entity.id)
      expect(initial_invoice.number).to start_with("BEEU-")
      expect(initial_invoice.fees_amount_cents).to eq(1000) # monthly plan paid in advance

      # NOTE: The upgrade moves the subscription to `us_entity`, so the terminated subscription stays
      #       on `eu_entity` while the new one bills under `us_entity`. An invoice holds a single
      #       billing entity, so the rotation must be billed on two separate invoices.
      travel_to(upgrade_at) do
        change_plan(yearly_plan, billing_entity_code: us_entity.code)
      end

      expect(subscription.reload).to be_terminated

      new_subscription = customer.subscriptions.order(created_at: :asc).last
      expect(new_subscription.plan.code).to eq(yearly_plan.code)
      expect(new_subscription).to be_active
      expect(new_subscription.billing_entity_id).to eq(us_entity.id)

      expect(customer.invoices.count).to eq(3)

      upgrade_invoice_eu = subscription.invoices.order(created_at: :asc).last
      expect(upgrade_invoice_eu.billing_entity_id).to eq(eu_entity.id)
      expect(upgrade_invoice_eu.number).to start_with("BEEU-")
      expect(upgrade_invoice_eu.sequential_id).to eq(2)
      expect(upgrade_invoice_eu.currency).to eq("EUR")
      expect(upgrade_invoice_eu.fees.map(&:subscription_id).uniq).to eq([subscription.id])
      expect(upgrade_invoice_eu.fees_amount_cents).to eq(5 * 100) # 5 API calls sent on Jun 12th, at 1 EUR

      upgrade_invoice_us = new_subscription.invoices.sole
      expect(upgrade_invoice_us.billing_entity_id).to eq(us_entity.id)
      expect(upgrade_invoice_us.number).to start_with("BEUS-")
      # NOTE: numbering is gapless per (customer, billing entity), so the US sequence starts at 1
      expect(upgrade_invoice_us.sequential_id).to eq(1)
      expect(upgrade_invoice_us.currency).to eq("EUR")
      expect(upgrade_invoice_us.fees.map(&:subscription_id).uniq).to eq([new_subscription.id])
      # NOTE: the yearly plan keeps the Jun 5th anniversary: Jun 20th 2024 to Jun 4th 2025 is 350 of 365 days
      expect(upgrade_invoice_us.fees_amount_cents).to eq((12_000 * 350.fdiv(365)).round)

      # NOTE: the unused part of the monthly plan is credited on the invoice that charged it, under `eu_entity`
      credit_note = customer.credit_notes.sole
      expect(credit_note.invoice).to eq(initial_invoice)
      expect(credit_note.invoice.billing_entity_id).to eq(eu_entity.id)
      # NOTE: Jun 20th to Jul 4th is 15 of the 30 days of the Jun 5th to Jul 4th period
      expect(credit_note.credit_amount_cents).to eq((1000 * 15.fdiv(30)).round)

      expect_invoices_billed_on_their_own_entity
      expect_no_failed_invoice

      # NOTE: the next yearly bill stays on `us_entity` and continues its sequence
      travel_to(DateTime.new(2025, 6, 5, 10, 0)) do
        expect { perform_billing }.to change { customer.invoices.count }.by(1)
      end

      renewal_invoice = new_subscription.invoices.order(created_at: :asc).last
      expect(renewal_invoice.billing_entity_id).to eq(us_entity.id)
      expect(renewal_invoice.sequential_id).to eq(2)
      expect(renewal_invoice.fees_amount_cents).to eq(12_000)
      expect(customer.invoices.where(billing_entity: eu_entity).count).to eq(2)

      expect_invoices_billed_on_their_own_entity
      expect_no_failed_invoice
    end
  end

  context "when the subscription inherits the customer's billing entity and the upgrade sets another one" do
    let(:subscription_billing_entity_code) { nil }

    it "bills the terminated subscription on the customer's entity and the upgraded one on the new entity" do
      subscription = customer.subscriptions.sole
      expect(subscription.billing_entity_id).to be_nil
      expect(subscription.invoices.sole.billing_entity_id).to eq(us_entity.id)

      travel_to(upgrade_at) do
        change_plan(yearly_plan, billing_entity_code: eu_entity.code)
      end

      expect(subscription.reload).to be_terminated

      new_subscription = customer.subscriptions.order(created_at: :asc).last
      expect(new_subscription.billing_entity_id).to eq(eu_entity.id)

      expect(customer.invoices.count).to eq(3)

      upgrade_invoice_us = subscription.invoices.order(created_at: :asc).last
      expect(upgrade_invoice_us.billing_entity_id).to eq(us_entity.id)
      expect(upgrade_invoice_us.sequential_id).to eq(2)
      expect(upgrade_invoice_us.fees_amount_cents).to eq(5 * 100) # 5 API calls sent on Jun 12th, at 1 EUR

      upgrade_invoice_eu = new_subscription.invoices.sole
      expect(upgrade_invoice_eu.billing_entity_id).to eq(eu_entity.id)
      expect(upgrade_invoice_eu.number).to start_with("BEEU-")
      expect(upgrade_invoice_eu.sequential_id).to eq(1)
      expect(upgrade_invoice_eu.fees_amount_cents).to eq((12_000 * 350.fdiv(365)).round) # 350 of 365 days

      expect_invoices_billed_on_their_own_entity
      expect_no_failed_invoice
    end
  end

  context "when the upgrade inherits the billing entity" do
    it "keeps billing the rotation on a single invoice" do
      subscription = customer.subscriptions.sole

      travel_to(upgrade_at) do
        change_plan(yearly_plan)
      end

      expect(subscription.reload).to be_terminated

      new_subscription = customer.subscriptions.order(created_at: :asc).last
      expect(new_subscription.billing_entity_id).to eq(eu_entity.id)

      expect(customer.invoices.count).to eq(2)

      upgrade_invoice = new_subscription.invoices.sole
      expect(upgrade_invoice.billing_entity_id).to eq(eu_entity.id)
      expect(upgrade_invoice.subscriptions).to contain_exactly(subscription, new_subscription)
      # NOTE: 5 API calls of the terminated subscription + 350 of 365 days of the yearly plan
      expect(upgrade_invoice.fees_amount_cents).to eq(5 * 100 + (12_000 * 350.fdiv(365)).round)

      expect_no_failed_invoice
    end
  end

  context "when a downgrade moves the subscription to another billing entity" do
    it "bills the terminated and the new subscription on their own billing entity's invoice at the end of the period" do
      subscription = customer.subscriptions.sole

      # NOTE: a downgrade only starts at the end of the current period (Jul 5th)
      travel_to(upgrade_at) do
        change_plan(downgrade_plan, billing_entity_code: us_entity.code)
      end

      expect(subscription.reload).to be_active
      expect(customer.invoices.count).to eq(1)

      travel_to(DateTime.new(2024, 7, 5, 10, 0)) do
        perform_billing
      end

      expect(subscription.reload).to be_terminated

      new_subscription = subscription.next_subscription
      expect(new_subscription).to be_active
      expect(new_subscription.billing_entity_id).to eq(us_entity.id)

      expect(customer.invoices.count).to eq(3)

      closing_invoice_eu = subscription.invoices.order(created_at: :asc).last
      expect(closing_invoice_eu.billing_entity_id).to eq(eu_entity.id)
      expect(closing_invoice_eu.sequential_id).to eq(2)
      expect(closing_invoice_eu.fees.map(&:subscription_id).uniq).to eq([subscription.id])
      expect(closing_invoice_eu.fees_amount_cents).to eq(5 * 100) # 5 API calls sent on Jun 12th, at 1 EUR

      starting_invoice_us = new_subscription.invoices.sole
      expect(starting_invoice_us.billing_entity_id).to eq(us_entity.id)
      expect(starting_invoice_us.number).to start_with("BEUS-")
      expect(starting_invoice_us.sequential_id).to eq(1)
      expect(starting_invoice_us.fees_amount_cents).to eq(500) # full month of the downgrade plan, paid in advance

      expect_invoices_billed_on_their_own_entity
      expect_no_failed_invoice
    end
  end
end
