# frozen_string_literal: true

require "rails_helper"

RSpec.describe PastUsageQuery do
  subject(:result) { described_class.call(organization:, pagination:, filters:) }

  let_it_be(:organization) { create(:organization) }
  let(:pagination) { nil }
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
  let(:filters) do
    {
      external_customer_id: customer.external_id,
      external_subscription_id: subscription.external_id
    }
  end

  let_it_be(:customer) { create_default(:customer, organization:) }
  let_it_be(:plan, refind: true) { create(:plan, organization:) }

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
    let_it_be(:billable_metric1) { create(:billable_metric, organization:) }
    let(:billable_metric_code) { billable_metric1&.code }
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

    let_it_be(:billable_metric2) { create(:billable_metric, organization:) }

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
    let(:charge_deleted_at) { nil }
    let(:charge) { create(:graduated_charge, :regroup_paid_fees, plan:, billable_metric:, deleted_at: charge_deleted_at) }
    let(:period1_from) { Time.zone.parse("2023-08-17T00:00:00") }
    let(:period1_to) { Time.zone.parse("2023-09-16T23:59:59") }
    let(:period2_from) { Time.zone.parse("2023-07-17T00:00:00") }
    let(:period2_to) { Time.zone.parse("2023-08-16T23:59:59") }
    let(:period1_invoice) { create(:invoice, organization:, customer:, invoice_type: :advance_charges) }
    let(:period1_reason) { :in_advance_charge_periodic }
    let(:period1_charges_to) { period1_to }
    let(:period1_regenerated_invoice_id) { nil }
    let(:period2_reason) { nil }
    let(:invoice_subscription1) do
      create(:invoice_subscription, organization:, subscription:, invoice: period1_invoice,
        invoicing_reason: period1_reason, regenerated_invoice_id: period1_regenerated_invoice_id,
        charges_from_datetime: period1_from, charges_to_datetime: period1_charges_to)
    end
    let(:invoice_subscription2) do
      create(:invoice_subscription, organization:, subscription:, invoicing_reason: period2_reason,
        charges_from_datetime: period2_from, charges_to_datetime: period2_to)
    end
    let(:fee_period) { {charges_from_datetime: period1_from, charges_to_datetime: period1_to} }
    let(:extra_fee_attributes) { {} }
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
        properties: fee_period,
        **extra_fee_attributes
      }
    end
    let(:free_fee_invoice) { nil }
    let!(:free_fee) { create(:charge_fee, **free_fee_attributes, invoice: free_fee_invoice) }
    let!(:paid_fee) do
      create(:charge_fee, organization:, subscription:, charge:, invoice: period1_invoice,
        units: 10, total_aggregated_units: 10, amount_cents: 500, properties: fee_period, **extra_fee_attributes)
    end

    it "includes free units from the same billing period" do
      expect(result.usage_periods.first.fees).to match_array([paid_fee, free_fee])
      expect(result.usage_periods.last.fees).to be_empty
      expect(free_fee.reload).to have_attributes(invoice_id: nil, payment_status: "pending")
    end

    context "when the free fee is already attached to the invoice" do
      let(:free_fee_invoice) { period1_invoice }

      it "does not count it twice" do
        expect(result.usage_periods.first.fees).to match_array([paid_fee, free_fee])
      end
    end

    context "with fees that do not qualify" do
      before do
        create(:charge_fee, **free_fee_attributes, amount_cents: 50, precise_amount_cents: 50)
        create(:charge_fee, **free_fee_attributes, payment_status: :failed, amount_cents: 50, precise_amount_cents: 50)
        create(:charge_fee, **free_fee_attributes, units: 0)
        create(:charge_fee, **free_fee_attributes, deleted_at: Time.current)
        create(:charge_fee, **free_fee_attributes, properties: {charges_from_datetime: period2_from, charges_to_datetime: period2_to})
        create(:charge_fee, **free_fee_attributes, properties: {})
      end

      it "excludes payable, zero-unit, discarded and other-period fees" do
        expect(result.usage_periods.first.fees).to match_array([paid_fee, free_fee])
      end
    end

    context "when a fee rounds down to zero cents" do
      let!(:rounded_fee) { create(:charge_fee, **free_fee_attributes, precise_amount_cents: 0.1) }

      it "includes it as it can never be paid and regrouped" do
        expect(result.usage_periods.first.fees).to match_array([paid_fee, free_fee, rounded_fee])
      end
    end

    context "with fees of other subscriptions sharing the external ID" do
      let(:other_subscription) { create(:subscription, customer:, plan:, external_id: subscription.external_id, status: :terminated) }
      let(:other_customer) { create(:customer, external_id: customer.external_id) }
      let(:foreign_subscription) { create(:subscription, customer: other_customer, external_id: subscription.external_id) }

      before do
        create(:charge_fee, **free_fee_attributes, subscription: other_subscription)
        create(:charge_fee, **free_fee_attributes, subscription: subscription2)
        create(:charge_fee, **free_fee_attributes, organization: other_customer.organization, subscription: foreign_subscription)
      end

      it "excludes other subscriptions and organizations" do
        expect(result.usage_periods.first.fees).to match_array([paid_fee, free_fee])
      end
    end

    context "with fees of charges that do not regroup" do
      let(:standalone_charge) { create(:graduated_charge, plan:, pay_in_advance: true, invoiceable: false) }
      let(:invoiceable_charge) { create(:graduated_charge, plan:, pay_in_advance: true, invoiceable: true) }

      before do
        create(:charge_fee, **free_fee_attributes, charge: standalone_charge)
        create(:charge_fee, **free_fee_attributes, charge: invoiceable_charge)
        create(:charge_fee, **free_fee_attributes, pay_in_advance: false)
      end

      it "excludes them and arrears fees" do
        expect(result.usage_periods.first.fees).to match_array([paid_fee, free_fee])
      end
    end

    context "with a billable metric filter" do
      let(:filters) do
        {
          external_customer_id: customer.external_id,
          external_subscription_id: subscription.external_id,
          billable_metric_code: billable_metric.code
        }
      end
      let(:other_charge) { create(:graduated_charge, :regroup_paid_fees, plan:) }

      before { create(:charge_fee, **free_fee_attributes, charge: other_charge) }

      it "applies it to free fees" do
        expect(result.usage_periods.first.fees).to match_array([paid_fee, free_fee])
      end
    end

    context "with charge filters, grouping and presentation breakdowns" do
      let(:charge_filter) { create(:charge_filter, charge:) }
      let(:extra_fee_attributes) { {charge_filter:, grouped_by: {region: "eu"}, events_count: 1} }

      before do
        [paid_fee, free_fee].each do |fee|
          create(:presentation_breakdown, fee:, organization:, presentation_by: {model: "basic"}, units: fee.units)
        end
      end

      it "includes free units at every level" do
        usage = V1::Customers::ChargeUsageSerializer.new(result.usage_periods.first.fees, root_name: "past_usage").serialize.sole
        expected_usage = {units: "50.0", total_aggregated_units: "50.0", events_count: 2, amount_cents: 500}

        expect(usage).to include(expected_usage)
        expect(usage[:filters].sole).to include(expected_usage)
        expect(usage[:grouped_usage].sole).to include(expected_usage)
        expect(usage[:grouped_usage].sole[:filters].sole).to include(expected_usage)
        expect(usage[:grouped_usage].sole[:filters].sole[:presentation_breakdowns].pluck(:units)).to match_array(["10.0", "40.0"])
      end
    end

    context "when the period was truncated by a termination" do
      let(:period1_charges_to) { period1_to - 10.days }

      it "includes the free fees, which keep the full period end" do
        expect(result.usage_periods.first.fees).to match_array([paid_fee, free_fee])
      end
    end

    context "when the charge is discarded" do
      let(:charge_deleted_at) { Time.current }

      it "retains its fees" do
        expect(result.usage_periods.first.fees).to match_array([paid_fee, free_fee])
      end
    end

    context "when loading multiple billing periods" do
      let(:pagination) { {page: 1, limit: 100} }
      let(:period_count) { 6 }
      let(:include_free_fees) { true }
      let(:period2_reason) { :subscription_periodic }
      let!(:earlier_periods) do
        (2...period_count).map do |offset|
          create(:invoice_subscription, organization:, subscription:, invoicing_reason: :subscription_periodic,
            charges_from_datetime: period1_from - offset.months, charges_to_datetime: period1_to - offset.months)
        end
      end
      let(:free_fee_periods) { [invoice_subscription2, *earlier_periods] }
      let(:queries) { [] }
      let(:subscriber) { ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] } }

      before do
        free_fee_periods.each do |period|
          create(:charge_fee, **free_fee_attributes,
            properties: {charges_from_datetime: period.charges_from_datetime, charges_to_datetime: period.charges_to_datetime})
        end
      end

      shared_examples "batched free usage" do
        it "batches the fee lookups across the page" do
          ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
            expect(result.usage_periods.size).to eq(period_count)
            expect(result.usage_periods.flat_map(&:fees).size).to eq(include_free_fees ? period_count + 1 : 1)
            expected_units = include_free_fees ? [50] + [40] * (period_count - 1) : [10] + [0] * (period_count - 1)
            expect(result.usage_periods.map { |period| period.fees.sum(&:units) }).to eq(expected_units)
          end

          period_queries = queries.select { |sql| sql.include?('FROM "invoice_subscriptions"') && !sql.include?("COUNT(") }
          free_fee_queries = queries.select { |sql| sql.include?('FROM "fees"') && sql.include?('"fees"."invoice_id" IS NULL') }
          invoiced_fee_queries = queries.select { |sql| sql.include?('FROM "fees" INNER JOIN "subscriptions"') }
          expect(period_queries.size).to eq(2)
          expect(free_fee_queries.size).to eq(1)
          expect(invoiced_fee_queries.size).to eq(1)
        end
      end

      include_examples "batched free usage"

      context "with a smaller page" do
        let(:period_count) { 2 }

        include_examples "batched free usage"
      end

      context "when no free fees qualify" do
        let(:include_free_fees) { false }
        let(:free_fee) { nil }
        let(:free_fee_periods) { [] }

        include_examples "batched free usage"
      end
    end

    context "with a regular invoice for the same period" do
      let(:regular_period_created_at) { Time.current }
      let!(:regular_period) do
        create(:invoice_subscription, organization:, subscription:, invoicing_reason: :subscription_periodic,
          charges_from_datetime: period1_from, charges_to_datetime: period1_to, created_at: regular_period_created_at)
      end

      it "includes free fees only in the regrouped invoice's usage" do
        expect(result.usage_periods.find { |period| period.invoice_subscription == regular_period }.fees).to be_empty
        expect(result.usage_periods.flat_map { |period| period.fees.to_a }).to match_array([paid_fee, free_fee])
      end

      context "when pagination excludes the regrouped invoice" do
        let(:pagination) { {page: 1, limit: 1} }
        let(:regular_period_created_at) { 1.day.from_now }

        it "does not move free usage into the regular invoice" do
          expect(result.usage_periods.sole.invoice_subscription).to eq(regular_period)
          expect(result.usage_periods.sole.fees).to be_empty
        end
      end
    end

    context "when the invoice has been regenerated" do
      let(:regenerated_invoice) { create(:invoice, organization:, customer:, invoice_type: :advance_charges) }
      let(:period1_regenerated_invoice_id) { regenerated_invoice.id }
      let!(:regenerated_period) do
        create(:invoice_subscription, organization:, subscription:, invoice: regenerated_invoice,
          invoicing_reason: :in_advance_charge_periodic,
          charges_from_datetime: period1_from, charges_to_datetime: period1_to,
          created_at: invoice_subscription1.created_at + 1.second)
      end
      let!(:regenerated_paid_fee) do
        create(:charge_fee, organization:, subscription:, charge:, invoice: regenerated_invoice,
          units: 10, total_aggregated_units: 10, amount_cents: 500, properties: fee_period)
      end

      it "assigns the free fees to the replacement and retains the historical period" do
        periods = result.usage_periods.index_by { |period| period.invoice_subscription.id }

        expect(periods.fetch(regenerated_period.id).fees).to match_array([regenerated_paid_fee, free_fee])
        expect(periods.fetch(invoice_subscription1.id).fees).to eq([paid_fee])
      end

      context "when only the superseded period is on the page" do
        let(:pagination) { {page: 2, limit: 1} }

        it "does not assign free fees to the superseded period" do
          expect(result.usage_periods.sole.invoice_subscription).to eq(invoice_subscription1)
          expect(result.usage_periods.sole.fees).to eq([paid_fee])
        end
      end
    end

    context "when the period has only a regular invoice" do
      let(:period1_reason) { :subscription_periodic }

      it "includes the free fees in that period" do
        expect(result.usage_periods.first.fees).to match_array([paid_fee, free_fee])
      end
    end

    context "when the regrouped invoice is stamped with a later period" do
      let(:fee_period) { {charges_from_datetime: period2_from, charges_to_datetime: period2_to} }
      let(:period2_reason) { :subscription_periodic }

      it "shows the free fees next to their regrouped paid fees rather than by stamp" do
        expect(result.usage_periods.first.fees).to match_array([paid_fee, free_fee])
        expect(result.usage_periods.last.fees).to be_empty
      end

      context "when only the regrouped invoice is on the page" do
        let(:pagination) { {page: 1, limit: 1} }

        it "still shows the free fees with it" do
          expect(result.usage_periods.sole.invoice_subscription).to eq(invoice_subscription1)
          expect(result.usage_periods.sole.fees).to match_array([paid_fee, free_fee])
        end
      end

      context "when paid fees of the period are also regrouped on an earlier invoice" do
        let(:pagination) { {page: 1, limit: 1} }
        let(:earlier_invoice) { create(:invoice, organization:, customer:, invoice_type: :advance_charges) }
        let!(:earlier_period) do
          create(:invoice_subscription, organization:, subscription:, invoice: earlier_invoice,
            invoicing_reason: :in_advance_charge_periodic,
            charges_from_datetime: period2_from, charges_to_datetime: period2_to,
            created_at: invoice_subscription1.created_at - 1.day)
        end
        let!(:earlier_paid_fee) do
          create(:charge_fee, organization:, subscription:, charge:, invoice: earlier_invoice,
            units: 10, total_aggregated_units: 10, amount_cents: 500, properties: fee_period)
        end

        it "does not show the free fees on the later invoice's page" do
          expect(result.usage_periods.sole.invoice_subscription).to eq(invoice_subscription1)
          expect(result.usage_periods.sole.fees).to eq([paid_fee])
        end

        context "when the earlier invoice is on the page" do
          let(:pagination) { {page: 3, limit: 1} }

          it "shows the free fees with it" do
            expect(result.usage_periods.sole.invoice_subscription).to eq(earlier_period)
            expect(result.usage_periods.sole.fees).to match_array([earlier_paid_fee, free_fee])
          end
        end
      end
    end

    context "when the plan has no regrouped charge" do
      let(:charge) { create(:graduated_charge, plan:, pay_in_advance: true, invoiceable: false) }
      let(:queries) { [] }
      let(:subscriber) { ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] } }

      it "skips the free-fee lookups" do
        ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
          expect(result.usage_periods.first.fees).to eq([paid_fee])
        end

        expect(queries.count { |sql| sql.include?('FROM "charges"') }).to eq(1)
        expect(queries.count { |sql| sql.include?('FROM "invoice_subscriptions"') }).to eq(1)
        expect(queries.count { |sql| sql.include?('FROM "fees"') && sql.include?('"fees"."invoice_id" IS NULL') }).to eq(0)
      end
    end
  end
end
