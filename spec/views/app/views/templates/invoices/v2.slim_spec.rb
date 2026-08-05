# frozen_string_literal: true

require "rails_helper"

RSpec.describe "templates/invoices/v2.slim" do
  subject(:rendered_template) do
    Slim::Template.new(template, 1, pretty: true).render(invoice)
  end

  let(:template) { Rails.root.join("app/views/templates/invoices/v2.slim") }

  let(:organization) { create(:organization, :with_static_values) }
  let(:billing_entity) { create(:billing_entity, :with_static_values, organization:) }
  let(:customer) { create(:customer, :with_static_values, organization:, billing_entity:) }

  let(:plan) do
    create(:plan, organization:, interval: "monthly", pay_in_advance: false, invoice_display_name: "Basic Plan")
  end
  let(:subscription) { create(:subscription, customer:, plan:, status: "active") }

  let(:invoice) do
    create(
      :invoice,
      organization:,
      billing_entity:,
      customer:,
      version_number: 2,
      number: "LAGO-202308-001",
      payment_due_date: Date.parse("2023-08-18"),
      issuing_date: Date.parse("2023-08-18"),
      invoice_type: :subscription,
      currency: "USD",
      total_amount_cents: 5000,
      fees_amount_cents: 5000,
      sub_total_excluding_taxes_amount_cents: 5000,
      sub_total_including_taxes_amount_cents: 5000
    )
  end

  let(:charges_from_datetime) { Time.zone.parse("2023-07-01 00:00:00") }
  let(:charges_to_datetime) { Time.zone.parse("2023-07-31 23:59:59") }

  let(:invoice_subscription) do
    create(
      :invoice_subscription,
      invoice:,
      subscription:,
      from_datetime: Time.zone.parse("2023-08-01 00:00:00"),
      to_datetime: Time.zone.parse("2023-08-31 23:59:59"),
      charges_from_datetime:,
      charges_to_datetime:,
      timestamp: Time.zone.parse("2023-07-31 23:59:59")
    )
  end

  let(:subscription_fee) do
    create(
      :fee,
      invoice:,
      subscription:,
      fee_type: :subscription,
      amount_cents: 2000,
      amount_currency: "USD",
      units: 1,
      unit_amount_cents: 2000,
      precise_unit_amount: 20.00,
      invoice_display_name: "Basic Plan - Monthly"
    )
  end

  before do
    I18n.locale = :en
    invoice_subscription
    subscription_fee
  end

  context "when invoice_type is subscription with usage charges" do
    let(:billable_metric) { create(:billable_metric, organization:) }
    let(:charge) { create(:standard_charge, plan:, billable_metric:, invoice_display_name: "API calls") }
    let(:charge_fee) do
      create(
        :charge_fee,
        invoice:,
        subscription:,
        charge:,
        amount_cents: 3000,
        amount_currency: "USD",
        units: 30,
        unit_amount_cents: 100,
        precise_unit_amount: 1.00,
        events_count: 30,
        invoice_display_name: "API calls",
        properties: {
          "charges_from_datetime" => "2023-07-01 00:00:00",
          "charges_to_datetime" => "2023-07-31 23:59:59"
        }
      )
    end

    before { charge_fee }

    it "renders correctly" do
      expect(rendered_template).to match_html_snapshot
    end
  end

  context "when subscription and charge boundaries are missing (legacy data)" do
    let(:invoice_subscription) do
      create(
        :invoice_subscription,
        invoice:,
        subscription:,
        from_datetime: nil,
        to_datetime: nil,
        charges_from_datetime: nil,
        charges_to_datetime: nil,
        timestamp: Time.zone.parse("2023-07-31 23:59:59")
      )
    end

    let(:billable_metric) { create(:billable_metric, organization:) }
    let(:charge) { create(:standard_charge, plan:, billable_metric:, invoice_display_name: "API calls") }
    let(:charge_fee) do
      create(
        :charge_fee,
        invoice:,
        subscription:,
        charge:,
        amount_cents: 3000,
        amount_currency: "USD",
        units: 30,
        unit_amount_cents: 100,
        precise_unit_amount: 1.00,
        events_count: 30,
        invoice_display_name: "API calls"
      )
    end

    before { charge_fee }

    it "renders correctly" do
      expect(rendered_template).to match_html_snapshot
    end
  end

  context "when a recurring metric produces a usage breakdown" do
    let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:) }
    let(:charge) { create(:standard_charge, plan:, billable_metric:, pay_in_advance: false, invoice_display_name: "Storage") }
    let(:charge_fee) do
      create(
        :charge_fee,
        invoice:,
        subscription:,
        charge:,
        amount_cents: 3000,
        amount_currency: "USD",
        units: 30,
        unit_amount_cents: 100,
        precise_unit_amount: 1.00,
        invoice_display_name: "Storage"
      )
    end

    let(:breakdown) do
      [
        BillableMetrics::Breakdown::Item.new(
          date: Date.parse("2023-07-01"),
          action: "add",
          amount: 10,
          duration: 31,
          total_duration: 31
        ),
        BillableMetrics::Breakdown::Item.new(
          date: Date.parse("2023-07-15"),
          action: "remove",
          amount: 4,
          duration: 17,
          total_duration: 31
        )
      ]
    end

    before do
      charge_fee
      # The breakdown is computed from the event store (covered by
      # BillableMetrics::Breakdown::SumService specs); here we stub it so the
      # template rendering is deterministic and independent of event data.
      allow(invoice).to receive(:recurring_breakdown).and_return(breakdown)
    end

    it "renders correctly" do
      expect(rendered_template).to match_html_snapshot
    end
  end
end
