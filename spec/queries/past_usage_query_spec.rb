# frozen_string_literal: true

require "rails_helper"

RSpec.describe PastUsageQuery do
  subject(:result) { described_class.call(organization:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:filters) do
    {
      external_customer_id: customer.external_id,
      external_subscription_id: subscription.external_id
    }
  end

  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:subscription2) { create(:subscription, customer:, plan:) }

  let(:invoice_subscription1) do
    create(
      :invoice_subscription,
      charges_from_datetime: DateTime.parse("2023-08-17T00:00:00"),
      charges_to_datetime: DateTime.parse("2023-09-16T23:59:59"),
      subscription:
    )
  end

  let(:invoice_subscription2) do
    create(
      :invoice_subscription,
      charges_from_datetime: DateTime.parse("2023-07-17T00:00:00"),
      charges_to_datetime: DateTime.parse("2023-08-16T23:59:59"),
      subscription:
    )
  end

  let(:invoice_subscription3) do
    create(
      :invoice_subscription,
      charges_from_datetime: DateTime.parse("2023-07-17T00:00:00"),
      charges_to_datetime: DateTime.parse("2023-08-16T23:59:59"),
      subscription: subscription2
    )
  end

  before do
    invoice_subscription1
    invoice_subscription2
  end

  it "returns a list of invoice_subscription" do
    expect(result).to be_success
    expect(result.usage_periods.count).to eq(2)
  end

  context "when invoice subscriptions have the same values for the ordering criteria" do
    let(:invoice_subscription2) do
      create(
        :invoice_subscription,
        id: "00000000-0000-0000-0000-000000000000",
        charges_from_datetime: invoice_subscription1.charges_from_datetime,
        charges_to_datetime: invoice_subscription1.charges_to_datetime,
        subscription:,
        created_at: invoice_subscription1.created_at
      )
    end

    it "returns a consistent list" do
      result_invoice_subscriptions_ids = result.usage_periods.map(&:invoice_subscription).map(&:id)

      expect(result).to be_success
      expect(result.usage_periods.count).to eq(2)
      expect(result_invoice_subscriptions_ids).to include(invoice_subscription1.id)
      expect(result_invoice_subscriptions_ids).to include(invoice_subscription2.id)
      expect(result_invoice_subscriptions_ids.index(invoice_subscription1.id))
        .to be > result_invoice_subscriptions_ids.index(invoice_subscription2.id)
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 2, limit: 2} }

    before do
      create(
        :invoice_subscription,
        charges_from_datetime: DateTime.parse("2023-06-17T00:00:00"),
        charges_to_datetime: DateTime.parse("2023-07-16T23:59:59"),
        subscription:
      )
    end

    it "applies the pagination" do
      expect(result).to be_success
      expect(result.current_page).to eq(2)
      expect(result.prev_page).to eq(1)
      expect(result.next_page).to be_nil
      expect(result.total_pages).to eq(2)
      expect(result.total_count).to eq(3)
    end
  end

  context "when external_customer_id is missing" do
    let(:filters) { {external_subscription_id: subscription.external_id} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages.keys).to include(:external_customer_id)
      expect(result.error.messages[:external_customer_id]).to include("value_is_mandatory")
    end
  end

  context "when external_subscription_id is missing" do
    let(:filters) { {external_customer_id: customer.external_id} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages.keys).to include(:external_subscription_id)
      expect(result.error.messages[:external_subscription_id]).to include("value_is_mandatory")
    end
  end

  context "with fees belonging to multiple subscriptions" do
    let(:billable_metric1) { create(:billable_metric, organization:) }
    let(:billable_metric_code) { billable_metric1&.code }

    let(:billable_metric2) { create(:billable_metric, organization:) }

    let(:charge1) { create(:standard_charge, plan:, billable_metric: billable_metric1) }
    let(:charge2) { create(:standard_charge, plan:, billable_metric: billable_metric2) }

    let(:fee1) { create(:charge_fee, charge: charge1, subscription:, invoice: invoice_subscription1.invoice) }
    let(:fee2) { create(:charge_fee, charge: charge2, subscription: subscription2, invoice: invoice_subscription1.invoice) }

    let(:filters) do
      {
        external_customer_id: customer.external_id,
        external_subscription_id: subscription.external_id
      }
    end

    before do
      invoice_subscription3
      fee1
      fee2
    end

    it "filters the fees accordingly" do
      expect(result).to be_success
      expect(result.usage_periods.count).to eq(2)
      expect(result.usage_periods.first.fees.count).to eq(1)
      expect(result.usage_periods.first.fees.first.subscription).to eq(subscription)
    end
  end

  context "with billable_metric_code" do
    let(:billable_metric1) { create(:billable_metric, organization:) }
    let(:billable_metric_code) { billable_metric1&.code }

    let(:billable_metric2) { create(:billable_metric, organization:) }

    let(:charge1) { create(:standard_charge, plan:, billable_metric: billable_metric1) }
    let(:charge2) { create(:standard_charge, plan:, billable_metric: billable_metric2) }

    let(:fee1) { create(:charge_fee, charge: charge1, subscription:, invoice: invoice_subscription1.invoice) }
    let(:fee2) { create(:charge_fee, charge: charge2, subscription:, invoice: invoice_subscription1.invoice) }

    let(:filters) do
      {
        external_customer_id: customer.external_id,
        external_subscription_id: subscription.external_id,
        billable_metric_code:
      }
    end

    before do
      fee1
      fee2
    end

    it "filters the fees accordingly" do
      expect(result).to be_success
      expect(result.usage_periods.count).to eq(2)
      expect(result.usage_periods.first.fees.count).to eq(1)
    end

    context "when billable metric is not found" do
      let(:billable_metric_code) { "unknown_code" }

      it "returns a not found failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.error_code).to eq("billable_metric_not_found")
      end
    end
  end

  context "with periods_count filter" do
    let(:periods_count) { 1 }
    let(:filters) do
      {
        external_customer_id: customer.external_id,
        external_subscription_id: subscription.external_id,
        periods_count:
      }
    end

    it "returns last requested periods" do
      expect(result).to be_success
      expect(result.usage_periods.count).to eq(1)
      expect(result.usage_periods.first.invoice_subscription).to eq(invoice_subscription1)
    end

    context "when periods_count is higher than billed period count" do
      let(:periods_count) { 10 }

      it "returns all periods" do
        expect(result).to be_success
        expect(result.usage_periods.count).to eq(2)
      end
    end
  end

  context "with unbilled free advance fees" do
    let(:billable_metric) { create(:sum_billable_metric, organization:) }
    let(:charge) { create(:graduated_charge, :regroup_paid_fees, plan:, billable_metric:) }
    let(:free_fee_attributes) do
      {
        organization:,
        subscription:,
        charge:,
        invoice: nil,
        pay_in_advance: true,
        amount_cents: 0,
        precise_amount_cents: 0,
        units: 40,
        total_aggregated_units: 40,
        properties: {
          charges_from_datetime: invoice_subscription1.charges_from_datetime,
          charges_to_datetime: invoice_subscription1.charges_to_datetime
        }
      }
    end
    let(:free_fee) { create(:charge_fee, **free_fee_attributes) }
    let(:paid_fee) do
      create(:charge_fee, organization:, subscription:, charge:, invoice: invoice_subscription1.invoice,
        units: 10, total_aggregated_units: 10, amount_cents: 500)
    end

    before do
      invoice_subscription1.update!(invoicing_reason: :in_advance_charge_periodic)
      invoice_subscription1.invoice.update!(invoice_type: :advance_charges)
      free_fee
      paid_fee
    end

    it "includes free units from the same billing period" do
      expect(result.usage_periods.first.fees).to match_array([paid_fee, free_fee])
      expect(result.usage_periods.last.fees).to be_empty
      expect(free_fee.reload).to have_attributes(invoice_id: nil, payment_status: "pending")
    end

    it "does not count free fees already attached to an invoice twice" do
      free_fee.update!(invoice: invoice_subscription1.invoice)

      expect(result.usage_periods.first.fees).to match_array([paid_fee, free_fee])
    end

    it "excludes payable, zero-unit, discarded and other-period fees" do
      create(:charge_fee, **free_fee_attributes, amount_cents: 50, precise_amount_cents: 50)
      create(:charge_fee, **free_fee_attributes, payment_status: :failed, amount_cents: 50, precise_amount_cents: 50)
      create(:charge_fee, **free_fee_attributes, precise_amount_cents: 0.1)
      create(:charge_fee, **free_fee_attributes, units: 0)
      create(:charge_fee, **free_fee_attributes, deleted_at: Time.current)
      create(:charge_fee, **free_fee_attributes, properties: {
        charges_from_datetime: invoice_subscription2.charges_from_datetime,
        charges_to_datetime: invoice_subscription2.charges_to_datetime
      })
      create(:charge_fee, **free_fee_attributes, properties: {})

      expect(result.usage_periods.first.fees).to match_array([paid_fee, free_fee])
    end

    it "excludes other subscriptions and organizations even when external IDs match" do
      other_subscription = create(:subscription, customer:, plan:, external_id: subscription.external_id, status: :terminated)
      create(:charge_fee, **free_fee_attributes, subscription: other_subscription)
      create(:charge_fee, **free_fee_attributes, subscription: subscription2)
      other_customer = create(:customer, external_id: customer.external_id)
      foreign_subscription = create(:subscription, customer: other_customer, external_id: subscription.external_id)
      create(:charge_fee, **free_fee_attributes, organization: other_customer.organization, subscription: foreign_subscription)

      expect(result.usage_periods.first.fees).to match_array([paid_fee, free_fee])
    end

    it "excludes charges without regrouping and invoiceable advance charges" do
      standalone_charge = create(:graduated_charge, plan:, pay_in_advance: true, invoiceable: false)
      invoiceable_charge = create(:graduated_charge, plan:, pay_in_advance: true, invoiceable: true)
      create(:charge_fee, **free_fee_attributes, charge: standalone_charge)
      create(:charge_fee, **free_fee_attributes, charge: invoiceable_charge)
      create(:charge_fee, **free_fee_attributes, pay_in_advance: false)

      expect(result.usage_periods.first.fees).to match_array([paid_fee, free_fee])
    end

    it "respects the billable metric filter for free fees" do
      filters[:billable_metric_code] = charge.billable_metric.code
      other_charge = create(:graduated_charge, :regroup_paid_fees, plan:)
      create(:charge_fee, **free_fee_attributes, charge: other_charge)

      expect(result.usage_periods.first.fees).to match_array([paid_fee, free_fee])
    end

    it "includes free units in charge filters, grouped usage and presentation breakdowns" do
      charge_filter = create(:charge_filter, charge:)
      [paid_fee, free_fee].each do |fee|
        fee.update!(charge_filter:, grouped_by: {region: "eu"}, events_count: 1)
        create(:presentation_breakdown, fee:, organization:, presentation_by: {model: "basic"}, units: fee.units)
      end

      usage = V1::Customers::ChargeUsageSerializer.new(result.usage_periods.first.fees, root_name: "past_usage").serialize.sole
      expected_usage = {units: "50.0", total_aggregated_units: "50.0", events_count: 2, amount_cents: 500}

      expect(usage).to include(expected_usage)
      expect(usage[:filters].sole).to include(expected_usage)
      expect(usage[:grouped_usage].sole).to include(expected_usage)
      expect(usage[:grouped_usage].sole[:filters].sole).to include(expected_usage)
      expect(usage[:grouped_usage].sole[:filters].sole[:presentation_breakdowns].pluck(:units)).to match_array(["10.0", "40.0"])
    end

    it "matches equivalent timestamps with a timezone offset" do
      free_fee.update!(properties: {
        charges_from_datetime: invoice_subscription1.charges_from_datetime.in_time_zone("Europe/Paris").iso8601,
        charges_to_datetime: invoice_subscription1.charges_to_datetime.in_time_zone("Europe/Paris").iso8601
      })

      expect(result.usage_periods.first.fees).to match_array([paid_fee, free_fee])
    end

    it "retains fees for discarded charges" do
      charge.discard!

      expect(result.usage_periods.first.fees).to match_array([paid_fee, free_fee])
    end

    context "with a regular invoice for the same period" do
      let!(:regular_period) do
        create(:invoice_subscription, organization:, subscription:,
          invoicing_reason: :subscription_periodic,
          charges_from_datetime: invoice_subscription1.charges_from_datetime,
          charges_to_datetime: invoice_subscription1.charges_to_datetime)
      end

      it "includes free fees only in the regrouped invoice's usage" do
        expect(result.usage_periods.find { |period| period.invoice_subscription == regular_period }.fees).to be_empty
        expect(result.usage_periods.flat_map { |period| period.fees.to_a }).to match_array([paid_fee, free_fee])
      end

      context "when pagination excludes the regrouped invoice" do
        let(:pagination) { {page: 1, limit: 1} }

        before { regular_period.update!(created_at: 1.day.from_now) }

        it "does not move free usage into the regular invoice" do
          expect(result.usage_periods.sole.invoice_subscription).to eq(regular_period)
          expect(result.usage_periods.sole.fees).to be_empty
        end
      end
    end

    context "when the period has only a regular invoice" do
      before { invoice_subscription1.update!(invoicing_reason: :subscription_periodic) }

      it "includes the free fees in that period" do
        expect(result.usage_periods.first.fees).to match_array([paid_fee, free_fee])
      end
    end
  end
end
