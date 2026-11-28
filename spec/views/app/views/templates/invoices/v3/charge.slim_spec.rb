# frozen_string_literal: true

require "rails_helper"

RSpec.describe "templates/invoices/v3/charge.slim" do
  subject(:rendered_template) do
    Slim::Template.new(template, 1, pretty: true).render(invoice)
  end

  let(:template) { Rails.root.join("app/views/templates/invoices/v3/charge.slim") }

  let(:organization) { create(:organization, :with_static_values) }
  let(:billing_entity) { organization.default_billing_entity }
  let(:customer) { create(:customer, :with_static_values, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }

  let(:plan) do
    create(
      :plan,
      organization:,
      interval: "monthly",
      pay_in_advance: false,
      invoice_display_name: "Monthly Plan"
    )
  end

  let(:subscription) do
    create(
      :subscription,
      customer:,
      plan:,
      status: "active",
      started_at: Time.zone.parse("2025-09-01 00:00:00"),
      subscription_at: Time.zone.parse("2025-09-01 00:00:00"),
      billing_time: :calendar
    )
  end

  let(:invoice) do
    create(
      :invoice,
      customer:,
      organization:,
      number: "LAGO-202509-CH-001",
      payment_due_date: Date.parse("2025-09-15"),
      issuing_date: Date.parse("2025-09-01"),
      invoice_type: :subscription,
      total_amount_cents: 10000,
      currency: "USD",
      fees_amount_cents: 10000,
      sub_total_excluding_taxes_amount_cents: 10000,
      sub_total_including_taxes_amount_cents: 10000,
      coupons_amount_cents: 0
    )
  end

  let(:invoice_subscription) do
    create(
      :invoice_subscription,
      invoice:,
      subscription:,
      from_datetime: Time.zone.parse("2025-09-01 00:00:00"),
      to_datetime: Time.zone.parse("2025-09-30 23:59:59"),
      charges_from_datetime: Time.zone.parse("2025-09-01 00:00:00"),
      charges_to_datetime: Time.zone.parse("2025-09-30 23:59:59"),
      timestamp: Time.zone.parse("2025-09-01 00:00:00")
    )
  end

  before do
    I18n.locale = :en
    invoice_subscription
  end

  context "with an advance_charges invoice" do
    let(:voided_invoice_id) { nil }
    let(:invoice) do
      create(
        :invoice,
        customer:,
        organization:,
        number: "LAGO-202509-CH-001",
        version_number: 3,
        payment_due_date: Date.parse("2025-09-15"),
        issuing_date: Date.parse("2025-09-01"),
        invoice_type: :advance_charges,
        voided_invoice_id:,
        total_amount_cents: 5000,
        currency: "USD",
        fees_amount_cents: 5000,
        sub_total_excluding_taxes_amount_cents: 5000,
        sub_total_including_taxes_amount_cents: 5000,
        coupons_amount_cents: 0
      )
    end
    let(:rendered_text) do
      document = Nokogiri::HTML(rendered_template)
      document.css("style").remove
      document.xpath("//body//text()").map(&:text).join(" ").squish
    end
    let(:due_date) { I18n.l(Date.new(2025, 9, 15), format: :default) }

    before do
      create(
        :charge_fee,
        invoice:,
        charge: create(:standard_charge, :pay_in_advance, plan:, billable_metric:),
        subscription:,
        pay_in_advance: true,
        amount_cents: 5000,
        amount_currency: "USD",
        units: 10,
        unit_amount_cents: 500,
        precise_unit_amount: 5.00,
        invoice_display_name: "API Calls",
        properties: {
          "from_datetime" => "2025-09-01 00:00:00",
          "to_datetime" => "2025-09-30 23:59:59",
          "charges_from_datetime" => "2025-09-01 00:00:00",
          "charges_to_datetime" => "2025-09-30 23:59:59"
        }
      )
    end

    it "renders a paid invoice with nothing due" do
      expect(rendered_text).to include("Paid invoice")
      expect(rendered_text).to include("$50.00 Already paid")
      expect(rendered_text).to include("Already paid $50.00")
      expect(rendered_text).not_to include("Due #{due_date}")
    end

    context "when it is regenerated from a voided invoice" do
      let(:voided_invoice_id) { create(:invoice, customer:, organization:, invoice_type: :advance_charges, status: :voided).id }

      it "renders like a regular invoice, with a due date and a total" do
        expect(rendered_text).to include("$50.00 Due #{due_date}")
        expect(rendered_text).to include("Total due $50.00")
        expect(rendered_text).not_to include("Already paid")
        expect(rendered_text).not_to include("Paid invoice")
      end
    end
  end
end
