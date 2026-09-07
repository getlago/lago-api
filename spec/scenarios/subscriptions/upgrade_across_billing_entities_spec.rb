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

  let(:monthly_plan) do
    create(:plan, organization:, interval: "monthly", amount_cents: 1000, pay_in_advance: true)
  end

  let(:yearly_plan) do
    create(:plan, organization:, interval: "yearly", amount_cents: 12_000, pay_in_advance: true)
  end

  let(:subscription_at) { DateTime.new(2024, 6, 5, 10, 0) }
  let(:upgrade_at) { DateTime.new(2024, 6, 20, 10, 0) }

  def upgrade_subscription(params = {})
    create_subscription(
      {
        external_customer_id: customer.external_id,
        external_id: customer.external_id,
        plan_code: yearly_plan.code,
        billing_time: "anniversary"
      }.merge(params)
    )
  end

  # NOTE: the subscription is bound to `eu_entity` while the customer's own (default) entity is `us_entity`
  before do
    travel_to(subscription_at) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: monthly_plan.code,
          billing_time: "anniversary",
          subscription_at: subscription_at.iso8601,
          billing_entity_code: eu_entity.code
        }
      )
    end
  end

  it "bills the terminated and the upgraded subscription on their own billing entity's invoice" do
    subscription = customer.subscriptions.sole
    expect(subscription.billing_entity_id).to eq(eu_entity.id)

    initial_invoice = subscription.invoices.sole
    expect(initial_invoice.billing_entity_id).to eq(eu_entity.id)
    expect(initial_invoice.number).to start_with("BEEU-")

    # NOTE: The upgrade moves the subscription to `us_entity`, so the terminated subscription stays
    #       on `eu_entity` while the new one bills under `us_entity`. An invoice holds a single
    #       billing entity, so the rotation must be billed on two separate invoices.
    travel_to(upgrade_at) do
      upgrade_subscription(billing_entity_code: us_entity.code)
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

    upgrade_invoice_us = new_subscription.invoices.sole
    expect(upgrade_invoice_us.billing_entity_id).to eq(us_entity.id)
    expect(upgrade_invoice_us.number).to start_with("BEUS-")
    # NOTE: numbering is gapless per (customer, billing entity), so the US sequence starts at 1
    expect(upgrade_invoice_us.sequential_id).to eq(1)

    # NOTE: no invoice ever mixes subscriptions from different billing entities
    customer.invoices.find_each do |invoice|
      expect(invoice.subscriptions.map(&:applicable_billing_entity_id).uniq).to eq([invoice.billing_entity_id])
    end
  end

  it "keeps billing the rotation on a single invoice when the upgrade inherits the billing entity" do
    subscription = customer.subscriptions.sole

    travel_to(upgrade_at) do
      upgrade_subscription
    end

    expect(subscription.reload).to be_terminated

    new_subscription = customer.subscriptions.order(created_at: :asc).last
    expect(new_subscription.billing_entity_id).to eq(eu_entity.id)

    expect(customer.invoices.count).to eq(2)

    upgrade_invoice = new_subscription.invoices.sole
    expect(upgrade_invoice.billing_entity_id).to eq(eu_entity.id)
    expect(upgrade_invoice.subscriptions).to contain_exactly(subscription, new_subscription)
  end
end
