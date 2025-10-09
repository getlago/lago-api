# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Customers::UsageController, type: :request do
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }

  let(:plan) { create(:plan, interval: "monthly") }

  let(:subscription) do
    create(
      :subscription,
      plan:,
      customer:,
      started_at: Time.zone.now - 2.years
    )
  end

  describe "GET /customers/:customer_id/current_usage" do
    subject do
      get_with_token(
        organization,
        "/api/v1/customers/#{customer.external_id}/current_usage",
        params
      )
    end

    let(:params) { {external_subscription_id: subscription.external_id} }
    let(:tax) { create(:tax, :applied_to_billing_entity, organization:, rate: 20) }
    let(:metric) { create(:billable_metric, aggregation_type: "count_agg") }

    let(:charge) do
      create(
        :graduated_charge,
        plan: subscription.plan,
        charge_model: "graduated",
        billable_metric: metric,
        properties: {
          graduated_ranges: [
            {
              from_value: 0,
              to_value: nil,
              per_unit_amount: "0.01",
              flat_amount: "0.01"
            }
          ]
        }
      )
    end

    before do
      subscription
      charge
      tax

      create_list(
        :event,
        4,
        organization:,
        customer:,
        subscription:,
        code: metric.code,
        timestamp: Time.zone.now
      )
    end

    include_examples "requires API permission", "customer_usage", "read"

    it "returns the usage for the customer" do
      subject

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:customer_usage][:from_datetime]).to eq(Time.zone.today.beginning_of_month.beginning_of_day.iso8601)
        expect(json[:customer_usage][:to_datetime]).to eq(Time.zone.today.end_of_month.end_of_day.iso8601)
        expect(json[:customer_usage][:issuing_date]).to eq(Time.zone.today.end_of_month.iso8601)
        expect(json[:customer_usage][:amount_cents]).to eq(5)
        expect(json[:customer_usage][:currency]).to eq("EUR")
        expect(json[:customer_usage][:total_amount_cents]).to eq(6)

        charge_usage = json[:customer_usage][:charges_usage].first
        expect(charge_usage[:billable_metric][:name]).to eq(metric.name)
        expect(charge_usage[:billable_metric][:code]).to eq(metric.code)
        expect(charge_usage[:billable_metric][:aggregation_type]).to eq("count_agg")
        expect(charge_usage[:charge][:charge_model]).to eq("graduated")
        expect(charge_usage[:units]).to eq("4.0")
        expect(charge_usage[:amount_cents]).to eq(5)
        expect(charge_usage[:amount_currency]).to eq("EUR")
      end
    end

    context "when apply_taxes is false" do
      let(:params) { {external_subscription_id: subscription.external_id, apply_taxes: false} }

      it "returns the usage for the customer without applying taxes" do
        subject

        aggregate_failures do
          expect(response).to have_http_status(:success)
          # With taxes disabled, fees_amount_cents remains 5 and no tax is added.
          expect(json[:customer_usage][:amount_cents]).to eq(5)
          expect(json[:customer_usage][:taxes_amount_cents]).to eq(0)
          expect(json[:customer_usage][:total_amount_cents]).to eq(5)
        end
      end
    end

    context "when apply_taxes is true" do
      let(:params) { {external_subscription_id: subscription.external_id, apply_taxes: true} }

      context "with a anrok provider" do
        let(:integration) { create(:anrok_integration, organization:) }
        let(:integration_customer) { create(:anrok_customer, integration:, customer:) }
        let(:double_checker) { instance_double(Throttling::Base) }

        before {
          integration_customer
          allow(Throttling).to receive(:for).with(:anrok).and_return(double_checker)
          allow(double_checker).to receive(:check).and_return(false)
        }

        it "rescue from provider throttles" do
          subject
          expect(response).to have_http_status(:too_many_requests)
          expect(response.body).to match(/anrok.*Try again later/)
        end
      end
    end

    context "with filters" do
      let(:filter_metric) { create(:billable_metric, aggregation_type: "count_agg", organization:) }
      let(:billable_metric_filter) do
        create(:billable_metric_filter, billable_metric: filter_metric, key: "cloud", values: %w[aws google])
      end

      let(:charge) do
        create(
          :standard_charge,
          plan: subscription.plan,
          billable_metric: filter_metric,
          properties: {amount: "0"}
        )
      end

      let(:charge_filter_aws) { create(:charge_filter, charge:, properties: {amount: "10"}) }
      let(:charge_filter_gcp) { create(:charge_filter, charge:, properties: {amount: "20"}) }

      let(:charge_filter_value_aws) do
        create(:charge_filter_value, charge_filter: charge_filter_aws, billable_metric_filter:, values: ["aws"])
      end

      let(:charge_filter_value_gcp) do
        create(:charge_filter_value, charge_filter: charge_filter_gcp, billable_metric_filter:, values: ["google"])
      end

      before do
        subscription
        charge
        tax
        charge_filter_value_aws
        charge_filter_value_gcp

        create_list(
          :event,
          3,
          organization:,
          customer:,
          subscription:,
          code: filter_metric.code,
          timestamp: Time.zone.now,
          properties: {cloud: "aws"}
        )

        create(
          :event,
          organization:,
          customer:,
          subscription:,
          code: filter_metric.code,
          timestamp: Time.zone.now,
          properties: {cloud: "google"}
        )
      end

      it "returns the filters usage for the customer" do
        subject

        charge_usage = json[:customer_usage][:charges_usage].first
        filters_usage = charge_usage[:filters]

        aws_filter_data = filters_usage.find { |f| f[:values] && f[:values][:cloud] == ["aws"] }
        gcp_filter_data = filters_usage.find { |f| f[:values] && f[:values][:cloud] == ["google"] }

        aggregate_failures do
          expect(charge_usage[:units]).to eq("4.0")
          expect(charge_usage[:amount_cents]).to eq(5000)

          # Assertions for the AWS filter
          expect(aws_filter_data[:units]).to eq("3.0")
          expect(aws_filter_data[:amount_cents]).to eq(3000)

          # Assertions for the GCP filter
          expect(gcp_filter_data[:units]).to eq("1.0")
          expect(gcp_filter_data[:amount_cents]).to eq(2000)
        end
      end
    end

    context "with multiple filter values" do
      let(:multi_filter_metric) { create(:billable_metric, aggregation_type: "count_agg", organization:) }
      let(:billable_metric_filter_cloud) do
        create(:billable_metric_filter, billable_metric: multi_filter_metric, key: "cloud", values: %w[aws google])
      end
      let(:billable_metric_filter_region) do
        create(:billable_metric_filter, billable_metric: multi_filter_metric, key: "region", values: %w[usa france])
      end

      let(:charge_filter_aws_usa) { create(:charge_filter, charge:, properties: {amount: "10"}) }
      let(:charge_filter_aws_france) { create(:charge_filter, charge:, properties: {amount: "20"}) }
      let(:charge_filter_google_usa) { create(:charge_filter, charge:, properties: {amount: "30"}) }

      let(:charge_filter_value11) do
        create(
          :charge_filter_value,
          charge_filter: charge_filter_aws_usa,
          billable_metric_filter: billable_metric_filter_cloud,
          values: ["aws"]
        )
      end
      let(:charge_filter_value12) do
        create(
          :charge_filter_value,
          charge_filter: charge_filter_aws_usa,
          billable_metric_filter: billable_metric_filter_region,
          values: ["usa"]
        )
      end

      let(:charge_filter_value21) do
        create(
          :charge_filter_value,
          charge_filter: charge_filter_aws_france,
          billable_metric_filter: billable_metric_filter_cloud,
          values: ["aws"]
        )
      end
      let(:charge_filter_value22) do
        create(
          :charge_filter_value,
          charge_filter: charge_filter_aws_france,
          billable_metric_filter: billable_metric_filter_region,
          values: ["france"]
        )
      end

      let(:charge_filter_value31) do
        create(
          :charge_filter_value,
          charge_filter: charge_filter_google_usa,
          billable_metric_filter: billable_metric_filter_cloud,
          values: ["google"]
        )
      end
      let(:charge_filter_value32) do
        create(
          :charge_filter_value,
          charge_filter: charge_filter_google_usa,
          billable_metric_filter: billable_metric_filter_region,
          values: ["usa"]
        )
      end

      let(:charge) do
        create(
          :standard_charge,
          plan: subscription.plan,
          billable_metric: multi_filter_metric,
          properties: {amount: "0"}
        )
      end

      before do
        subscription
        charge
        tax
        charge_filter_value11
        charge_filter_value12
        charge_filter_value21
        charge_filter_value22
        charge_filter_value31
        charge_filter_value32

        create_list(
          :event,
          2,
          organization:,
          customer:,
          subscription:,
          code: multi_filter_metric.code,
          timestamp: Time.zone.now,
          properties: {cloud: "aws", region: "usa"}
        )

        create(
          :event,
          organization:,
          customer:,
          subscription:,
          code: multi_filter_metric.code,
          timestamp: Time.zone.now,
          properties: {cloud: "aws", region: "france"}
        )

        create(
          :event,
          organization:,
          customer:,
          subscription:,
          code: multi_filter_metric.code,
          timestamp: Time.zone.now,
          properties: {cloud: "google", region: "usa"}
        )
      end

      it "returns the filters usage for the customer" do
        subject

        charge_usage = json[:customer_usage][:charges_usage].first
        filters_usage = charge_usage[:filters]

        aws_usa_data = filters_usage.find { |f| f[:values] && f[:values][:cloud] == ["aws"] && f[:values][:region] == ["usa"] }
        aws_france_data = filters_usage.find { |f| f[:values] && f[:values][:cloud] == ["aws"] && f[:values][:region] == ["france"] }
        google_usa_data = filters_usage.find { |f| f[:values] && f[:values][:cloud] == ["google"] && f[:values][:region] == ["usa"] }

        aggregate_failures do
          expect(charge_usage[:units]).to eq("4.0")
          expect(charge_usage[:amount_cents]).to eq(7000)

          # Assertions for AWS/USA filter
          expect(aws_usa_data[:units]).to eq("2.0")
          expect(aws_usa_data[:amount_cents]).to eq(2000)

          # Assertions for AWS/France filter
          expect(aws_france_data[:units]).to eq("1.0")
          expect(aws_france_data[:amount_cents]).to eq(2000)

          # Assertions for Google/USA filter
          expect(google_usa_data[:units]).to eq("1.0")
          expect(google_usa_data[:amount_cents]).to eq(3000)
        end
      end
    end

    context "when customer does not belongs to the organization" do
      let(:customer) { create(:customer) }

      it "returns not found" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /customers/:customer_id/past_usage" do
    subject do
      get_with_token(
        organization,
        "/api/v1/customers/#{customer.external_id}/past_usage",
        params
      )
    end

    let(:params) { {external_subscription_id: subscription.external_id, periods_count: 2} }

    let(:invoice_subscription) do
      create(
        :invoice_subscription,
        charges_from_datetime: DateTime.parse("2023-08-17T00:00:00"),
        charges_to_datetime: DateTime.parse("2023-09-16T23:59:59"),
        subscription:
      )
    end

    let(:billable_metric1) { create(:billable_metric, organization:) }
    let(:billable_metric2) { create(:billable_metric, organization:) }

    let(:charge1) { create(:standard_charge, plan:, billable_metric: billable_metric1) }
    let(:charge2) { create(:standard_charge, plan:, billable_metric: billable_metric2) }

    let(:invoice) { invoice_subscription.invoice }

    let(:fee1) { create(:charge_fee, charge: charge1, subscription:, invoice:) }
    let(:fee2) { create(:charge_fee, charge: charge2, subscription:, invoice:) }

    before do
      fee1
      fee2
    end

    include_examples "requires API permission", "customer_usage", "read"

    it "returns the past usage" do
      subject

      aggregate_failures do
        expect(response).to have_http_status(:success)

        expect(json[:usage_periods].count).to eq(1)

        usage = json[:usage_periods].first
        expect(usage[:from_datetime]).to eq(invoice_subscription.charges_from_datetime.iso8601)
        expect(usage[:to_datetime]).to eq(invoice_subscription.charges_to_datetime.iso8601)
        expect(usage[:issuing_date]).to eq(invoice.issuing_date.iso8601)
        expect(usage[:currency]).to eq(invoice.currency)
        expect(usage[:amount_cents]).to eq(invoice.fees_amount_cents)
        expect(usage[:total_amount_cents]).to eq(4)
        expect(usage[:taxes_amount_cents]).to eq(4)

        expect(usage[:charges_usage].count).to eq(2)

        charge_usage = usage[:charges_usage].first
        expect(charge_usage[:billable_metric][:name]).to eq(billable_metric1.name)
        expect(charge_usage[:billable_metric][:code]).to eq(billable_metric1.code)
        expect(charge_usage[:billable_metric][:aggregation_type]).to eq(billable_metric1.aggregation_type)
        expect(charge_usage[:charge][:charge_model]).to eq(charge1.charge_model)
        expect(charge_usage[:units]).to eq(fee1.units.to_s)
        expect(charge_usage[:amount_cents]).to eq(fee1.amount_cents)
        expect(charge_usage[:amount_currency]).to eq(fee1.currency)
      end
    end

    context "when missing external_subscription_id" do
      let(:params) { {} }

      it "returns an unprocessable entity" do
        subject
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "with invalid billable metric code" do
      let(:params) do
        {
          billable_metric_code: "invalid_code",
          external_subscription_id: subscription.external_id
        }
      end

      it "returns a not found error" do
        subject
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
