# frozen_string_literal: true

require "rails_helper"

describe "Customer usage Scenario", cache: :redis do
  let(:organization) { create(:organization, webhook_url: nil) }

  let(:timezone) { "UTC" }
  let(:customer) { create(:customer, organization:, timezone:, currency: "EUR") }

  let(:plan) { create(:plan, organization:, amount_cents: 5000, pay_in_advance: false, interval: "yearly") }
  let(:billable_metric) { create(:billable_metric, organization:, code: "image_generation", name: "Image generation") }
  let(:charge) { create(:standard_charge, plan:, billable_metric:, invoice_display_name: "Image generation") }

  before { charge }

  def customer_usage_json(units: 1.0, from_datetime: "2043-01-01T09:30:00Z", to_datetime: "2043-12-31T23:59:59Z")
    total_amount_cents = 1000 * units
    {
      customer_usage: {
        amount_cents: total_amount_cents,
        charges_usage: [
          {
            amount_cents: total_amount_cents,
            amount_currency: "EUR",
            billable_metric: {
              aggregation_type: "count_agg",
              code: "image_generation",
              lago_id: billable_metric.id,
              name: billable_metric.name
            },
            charge: {
              charge_model: "standard",
              invoice_display_name: "Image generation",
              lago_id: charge.id
            },
            events_count: units.to_i,
            filters: [],
            grouped_usage: [],
            pricing_unit_details: nil,
            total_aggregated_units: units.to_d.to_s,
            units: units.to_d.to_s
          }
        ],
        currency: "EUR",
        from_datetime: from_datetime,
        issuing_date: to_datetime.slice(0, 10),
        lago_invoice_id: nil,
        taxes_amount_cents: 0,
        to_datetime: to_datetime,
        total_amount_cents: total_amount_cents
      }
    }
  end

  def fetch_and_assert_current_usage(units: 1.0, from_datetime: "2043-01-01T09:30:00Z", to_datetime: "2043-12-31T23:59:59Z")
    subscription = customer.subscriptions.first
    fetch_current_usage(customer:, subscription:)

    expect(json).to eq(customer_usage_json(units: units, from_datetime: from_datetime, to_datetime: to_datetime))
  end

  context "with start date in the past" do
    it "retrieve the customer usage" do
      travel_to(DateTime.new(2043, 8, 8, 9, 30)) do
        subscription = create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
            subscription_at: DateTime.new(2043, 1, 1, 9, 30).iso8601
          },
          as: :model
        )

        fetch_and_assert_current_usage(units: 0)

        create_event({
          external_subscription_id: subscription.external_id,
          timestamp: Time.now.to_f,
          code: "image_generation",
          properties: {}
        })

        fetch_and_assert_current_usage(units: 1)

        # test cache
        fetch_and_assert_current_usage(units: 1)

        create_event({
          external_subscription_id: subscription.external_id,
          timestamp: Time.now.to_f,
          code: "image_generation",
          properties: {}
        })

        fetch_and_assert_current_usage(units: 2)

        Event.last.discard

        # test cache
        fetch_and_assert_current_usage(units: 2)

        Rails.cache.clear

        fetch_and_assert_current_usage(units: 1)
      end
    end

    context "with Europe/Berlin timezone" do
      let(:timezone) { "Europe/Berlin" }

      it "retrieve the customer usage" do
        travel_to(DateTime.new(2043, 8, 8, 9, 30)) do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              subscription_at: DateTime.new(2043, 1, 1, 9, 30).iso8601
            }
          )

          fetch_and_assert_current_usage(units: 0, from_datetime: "2043-01-01T09:30:00Z", to_datetime: "2043-12-31T22:59:59Z")
        end
      end
    end

    context "with America/Los_Angeles timezone" do
      let(:timezone) { "America/Los_Angeles" }

      it "retrieve the customer usage" do
        travel_to(DateTime.new(2043, 8, 8, 9, 30)) do
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              subscription_at: DateTime.new(2043, 1, 1, 9, 30).iso8601
            }
          )

          fetch_and_assert_current_usage(units: 0, from_datetime: "2043-01-01T09:30:00Z", to_datetime: "2044-01-01T07:59:59Z")
        end
      end
    end

    context "with multiple charges and cache isolation" do
      let(:billable_metric_b) { create(:billable_metric, organization:, code: "api_calls", name: "API calls") }
      let(:charge_b) { create(:standard_charge, plan:, billable_metric: billable_metric_b, invoice_display_name: "API calls") }

      before { charge_b }

      it "caches each charge independently and invalidates only the affected charge" do
        travel_to(DateTime.new(2043, 8, 8, 9, 30)) do
          subscription = create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              subscription_at: DateTime.new(2043, 1, 1, 9, 30).iso8601
            },
            as: :model
          )

          # Send event for metric A
          create_event({
            external_subscription_id: subscription.external_id,
            timestamp: Time.now.to_f,
            code: "image_generation",
            properties: {}
          })

          fetch_current_usage(customer:, subscription:)
          charges_usage = json[:customer_usage][:charges_usage]
          expect(charges_usage.size).to eq(2)

          api_usage = charges_usage.find { |c| c[:billable_metric][:code] == "api_calls" }
          img_usage = charges_usage.find { |c| c[:billable_metric][:code] == "image_generation" }
          expect(img_usage[:units]).to eq("1.0")
          expect(api_usage[:units]).to eq("0.0")

          # Second fetch should use cache and return same results
          fetch_current_usage(customer:, subscription:)
          charges_usage = json[:customer_usage][:charges_usage]
          img_usage = charges_usage.find { |c| c[:billable_metric][:code] == "image_generation" }
          api_usage = charges_usage.find { |c| c[:billable_metric][:code] == "api_calls" }
          expect(img_usage[:units]).to eq("1.0")
          expect(api_usage[:units]).to eq("0.0")

          # Send event for metric B only — should invalidate only metric B's cache
          create_event({
            external_subscription_id: subscription.external_id,
            timestamp: Time.now.to_f,
            code: "api_calls",
            properties: {}
          })

          fetch_current_usage(customer:, subscription:)
          charges_usage = json[:customer_usage][:charges_usage]
          img_usage = charges_usage.find { |c| c[:billable_metric][:code] == "image_generation" }
          api_usage = charges_usage.find { |c| c[:billable_metric][:code] == "api_calls" }
          expect(img_usage[:units]).to eq("1.0")
          expect(api_usage[:units]).to eq("1.0")
        end
      end
    end

    context "with grouped_by and cache" do
      let(:charge) do
        create(:standard_charge, plan:, billable_metric:,
          invoice_display_name: "Image generation",
          properties: {amount: "10", grouped_by: %w[region]})
      end

      it "preserves grouped_by nil values through the cache" do
        travel_to(DateTime.new(2043, 8, 8, 9, 30)) do
          subscription = create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              subscription_at: DateTime.new(2043, 1, 1, 9, 30).iso8601
            },
            as: :model
          )

          # Event with region
          create_event({
            external_subscription_id: subscription.external_id,
            timestamp: Time.now.to_f,
            code: "image_generation",
            properties: {region: "us"}
          })

          # Event without region (nil group key)
          create_event({
            external_subscription_id: subscription.external_id,
            timestamp: Time.now.to_f,
            code: "image_generation",
            properties: {}
          })

          fetch_current_usage(customer:, subscription:)
          grouped_usage = json[:customer_usage][:charges_usage].first[:grouped_usage]
          expect(grouped_usage.size).to eq(2)

          us_group = grouped_usage.find { |g| g[:grouped_by][:region] == "us" }
          nil_group = grouped_usage.find { |g| g[:grouped_by][:region].nil? }
          expect(us_group[:units]).to eq("1.0")
          expect(nil_group[:units]).to eq("1.0")

          # Second fetch should use cache and return identical grouped results
          fetch_current_usage(customer:, subscription:)
          grouped_usage = json[:customer_usage][:charges_usage].first[:grouped_usage]
          expect(grouped_usage.size).to eq(2)

          us_group = grouped_usage.find { |g| g[:grouped_by][:region] == "us" }
          nil_group = grouped_usage.find { |g| g[:grouped_by][:region].nil? }
          expect(us_group[:units]).to eq("1.0")
          expect(nil_group[:units]).to eq("1.0")

          # New event invalidates cache, updated totals
          create_event({
            external_subscription_id: subscription.external_id,
            timestamp: Time.now.to_f,
            code: "image_generation",
            properties: {region: "us"}
          })

          fetch_current_usage(customer:, subscription:)
          grouped_usage = json[:customer_usage][:charges_usage].first[:grouped_usage]
          us_group = grouped_usage.find { |g| g[:grouped_by][:region] == "us" }
          nil_group = grouped_usage.find { |g| g[:grouped_by][:region].nil? }
          expect(us_group[:units]).to eq("2.0")
          expect(nil_group[:units]).to eq("1.0")
        end
      end
    end

    context "with charge filters and cache" do
      let(:billable_metric_filter) do
        create(:billable_metric_filter, billable_metric:, key: "cloud", values: %w[aws gcp])
      end
      let(:charge_filter) do
        create(:charge_filter, charge:, properties: {amount: "20"})
      end
      let(:charge_filter_value) do
        create(:charge_filter_value, charge_filter:, billable_metric_filter:, values: %w[aws])
      end

      before { charge_filter_value }

      it "caches filtered usage correctly" do
        travel_to(DateTime.new(2043, 8, 8, 9, 30)) do
          subscription = create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              subscription_at: DateTime.new(2043, 1, 1, 9, 30).iso8601
            },
            as: :model
          )

          # Event matching the aws filter
          create_event({
            external_subscription_id: subscription.external_id,
            timestamp: Time.now.to_f,
            code: "image_generation",
            properties: {cloud: "aws"}
          })

          # Event not matching any filter (default charge pricing)
          create_event({
            external_subscription_id: subscription.external_id,
            timestamp: Time.now.to_f,
            code: "image_generation",
            properties: {cloud: "gcp"}
          })

          fetch_current_usage(customer:, subscription:)
          charge_usage = json[:customer_usage][:charges_usage].first
          expect(charge_usage[:units]).to eq("2.0")
          # aws filter: 1 unit * 20 = 2000, default: 1 unit * 10 = 1000
          expect(charge_usage[:amount_cents]).to eq(3000)
          expect(charge_usage[:filters].size).to eq(2)

          aws_filter = charge_usage[:filters].find { |f| f[:values] == {cloud: %w[aws]} }
          default_filter = charge_usage[:filters].find { |f| f[:values].nil? }
          expect(aws_filter[:units]).to eq("1.0")
          expect(aws_filter[:amount_cents]).to eq(2000)
          expect(default_filter[:units]).to eq("1.0")
          expect(default_filter[:amount_cents]).to eq(1000)

          # Second fetch should use cache
          fetch_current_usage(customer:, subscription:)
          charge_usage = json[:customer_usage][:charges_usage].first
          expect(charge_usage[:amount_cents]).to eq(3000)
          expect(charge_usage[:filters].size).to eq(2)

          # New event invalidates cache
          create_event({
            external_subscription_id: subscription.external_id,
            timestamp: Time.now.to_f,
            code: "image_generation",
            properties: {cloud: "aws"}
          })

          fetch_current_usage(customer:, subscription:)
          charge_usage = json[:customer_usage][:charges_usage].first
          expect(charge_usage[:units]).to eq("3.0")
          # aws filter: 2 units * 20 = 4000, default: 1 unit * 10 = 1000
          expect(charge_usage[:amount_cents]).to eq(5000)
        end
      end
    end

    context "with charge update invalidating cache" do
      it "reflects updated charge properties after cache key changes" do
        travel_to(DateTime.new(2043, 8, 8, 9, 30)) do
          subscription = create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              subscription_at: DateTime.new(2043, 1, 1, 9, 30).iso8601
            },
            as: :model
          )

          create_event({
            external_subscription_id: subscription.external_id,
            timestamp: Time.now.to_f,
            code: "image_generation",
            properties: {}
          })

          # Initial usage: 1 unit * 10 = 1000 cents
          fetch_and_assert_current_usage(units: 1)

          # Cache should serve same result
          fetch_and_assert_current_usage(units: 1)

          # Update charge amount from 10 to 20 (this changes charge.updated_at, invalidating cache key)
          update_plan(plan, {
            charges: [{
              id: charge.id,
              billable_metric_id: billable_metric.id,
              charge_model: "standard",
              invoice_display_name: "Image generation",
              properties: {amount: "20"}
            }]
          })

          # Usage should reflect new price: 1 unit * 20 = 2000 cents
          fetch_current_usage(customer:, subscription:)
          expect(json[:customer_usage][:charges_usage].first[:amount_cents]).to eq(2000)
          expect(json[:customer_usage][:charges_usage].first[:units]).to eq("1.0")
        end
      end
    end
  end

  context "with filter_by_charge and filter_by_group filtering" do
    let(:plan) { create(:plan, organization:, amount_cents: 0, pay_in_advance: false, interval: "monthly") }

    let(:billable_metric_1) { create(:sum_billable_metric, organization:, field_name: "units") }
    let(:billable_metric_2) { create(:sum_billable_metric, organization:, field_name: "units") }

    let(:charge_1) do
      create(
        :standard_charge,
        plan:,
        billable_metric: billable_metric_1,
        properties: {amount: "10", pricing_group_keys: ["user"]}
      )
    end
    let(:charge_2) do
      create(
        :standard_charge,
        plan:,
        billable_metric: billable_metric_2,
        properties: {amount: "5", pricing_group_keys: ["user"]}
      )
    end

    let(:subscription) do
      sub = nil
      travel_to(DateTime.new(2024, 3, 1, 10, 0)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
            billing_time: "anniversary"
          }
        )
        sub = customer.subscriptions.first
      end
      sub
    end

    before do
      charge_1
      charge_2
      subscription
      travel_to(DateTime.new(2024, 3, 5, 10, 0)) do
        # Send 10 events for charge_1's metric with user 0..9
        10.times do |i|
          create_event(
            {
              code: billable_metric_1.code,
              transaction_id: SecureRandom.uuid,
              external_subscription_id: subscription.external_id,
              properties: {user: i.to_s, units: 5}
            }
          )
        end

        # Send 10 events for charge_2's metric with user 0..9
        10.times do |i|
          create_event(
            {
              code: billable_metric_2.code,
              transaction_id: SecureRandom.uuid,
              external_subscription_id: subscription.external_id,
              properties: {user: i.to_s, units: 3}
            }
          )
        end
      end
    end

    it "with filter_by_group returns one fee per charge filtered to that group" do
      travel_to(DateTime.new(2024, 3, 10, 10, 0)) do
        result = Invoices::CustomerUsageService.call(
          customer:,
          subscription:,
          apply_taxes: false,
          with_cache: false,
          usage_filters: UsageFilters.new(filter_by_group: {user: ["0"]})
        )

        expect(result).to be_success

        fees = result.usage.fees
        expect(fees.size).to eq(2)

        fee_1 = fees.find { |f| f.charge_id == charge_1.id }
        expect(fee_1.units).to eq(5)
        expect(fee_1.events_count).to eq(1)
        expect(fee_1.amount_cents).to eq(5_000) # 5 units * 10 amount * 100 cents

        fee_2 = fees.find { |f| f.charge_id == charge_2.id }
        expect(fee_2.units).to eq(3)
        expect(fee_2.events_count).to eq(1)
        expect(fee_2.amount_cents).to eq(1_500) # 3 units * 5 amount * 100 cents
      end
    end

    it "with filter_by_charge returns all grouped usage for that charge" do
      travel_to(DateTime.new(2024, 3, 10, 10, 0)) do
        result = Invoices::CustomerUsageService.call(
          customer:,
          subscription:,
          apply_taxes: false,
          with_cache: false,
          usage_filters: UsageFilters.new(filter_by_charge_id: charge_1.id)
        )

        expect(result).to be_success

        fees = result.usage.fees
        # 10 groups (user 0..9), all for charge_1
        expect(fees.size).to eq(10)
        expect(fees.map(&:charge_id).uniq).to eq([charge_1.id])

        fees.each do |fee|
          expect(fee.units).to eq(5)
          expect(fee.events_count).to eq(1)
          expect(fee.amount_cents).to eq(5_000)
        end

        expect(fees.map { |f| f.grouped_by["user"] }).to match_array(
          (0..9).map(&:to_s)
        )
      end
    end
  end

  context "with multi-level pricing_group_keys filtering by workspace" do
    let(:plan) { create(:plan, organization:, amount_cents: 0, pay_in_advance: false, interval: "monthly") }
    let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "units") }

    let(:charge) do
      create(
        :standard_charge,
        plan:,
        billable_metric:,
        properties: {amount: "10", pricing_group_keys: %w[workspace user]}
      )
    end

    let(:subscription) do
      sub = nil
      travel_to(DateTime.new(2024, 3, 1, 10, 0)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
            billing_time: "anniversary"
          }
        )
        sub = customer.subscriptions.first
      end
      sub
    end

    before do
      charge
      subscription
      travel_to(DateTime.new(2024, 3, 5, 10, 0)) do
        # Send 10 events for different users across two workspaces
        # workspace_a: users 0..4, workspace_b: users 5..9
        10.times do |i|
          workspace = (i < 5) ? "workspace_a" : "workspace_b"
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_subscription_id: subscription.external_id,
              properties: {workspace:, user: i.to_s, units: 3}
            }
          )
        end
      end
    end

    it "filtering by workspace still returns fees divided by user" do
      travel_to(DateTime.new(2024, 3, 10, 10, 0)) do
        result = Invoices::CustomerUsageService.call(
          customer:,
          subscription:,
          apply_taxes: false,
          with_cache: false,
          usage_filters: UsageFilters.new(filter_by_group: {workspace: ["workspace_a"]})
        )

        expect(result).to be_success

        fees = result.usage.fees
        # 5 users in workspace_a, each with their own fee grouped by user
        expect(fees.size).to eq(5)

        fees.each do |fee|
          expect(fee.charge_id).to eq(charge.id)
          expect(fee.units).to eq(3)
          expect(fee.events_count).to eq(1)
          expect(fee.amount_cents).to eq(3_000) # 3 units * 10 amount * 100 cents
        end

        expect(fees.map { |f| f.grouped_by["user"] }).to match_array(
          (0..4).map(&:to_s)
        )
      end
    end

    it "filtering by the other workspace returns only its users" do
      travel_to(DateTime.new(2024, 3, 10, 10, 0)) do
        result = Invoices::CustomerUsageService.call(
          customer:,
          subscription:,
          apply_taxes: false,
          with_cache: false,
          usage_filters: UsageFilters.new(filter_by_group: {workspace: ["workspace_b"]})
        )

        expect(result).to be_success

        fees = result.usage.fees
        expect(fees.size).to eq(5)

        fees.each do |fee|
          expect(fee.charge_id).to eq(charge.id)
          expect(fee.units).to eq(3)
          expect(fee.events_count).to eq(1)
          expect(fee.amount_cents).to eq(3_000)
        end

        expect(fees.map { |f| f.grouped_by["user"] }).to match_array(
          (5..9).map(&:to_s)
        )
      end
    end

    it "without filter returns fees grouped by both workspace and user" do
      travel_to(DateTime.new(2024, 3, 10, 10, 0)) do
        result = Invoices::CustomerUsageService.call(
          customer:,
          subscription:,
          apply_taxes: false,
          with_cache: false
        )

        expect(result).to be_success

        fees = result.usage.fees
        # 10 unique workspace+user combinations
        expect(fees.size).to eq(10)

        fees.each do |fee|
          expect(fee.charge_id).to eq(charge.id)
          expect(fee.units).to eq(3)
          expect(fee.events_count).to eq(1)
          expect(fee.amount_cents).to eq(3_000)
          expect(fee.grouped_by.keys).to match_array(%w[workspace user])
        end
      end
    end

    it "with skip_grouping returns a single aggregated fee" do
      travel_to(DateTime.new(2024, 3, 10, 10, 0)) do
        result = Invoices::CustomerUsageService.call(
          customer:,
          subscription:,
          apply_taxes: false,
          with_cache: false,
          usage_filters: UsageFilters.new(skip_grouping: true)
        )

        expect(result).to be_success

        fees = result.usage.fees
        # All 10 events aggregated into a single fee
        expect(fees.size).to eq(1)
        expect(fees.first.charge_id).to eq(charge.id)
        expect(fees.first.units).to eq(30) # 10 events * 3 units each
        expect(fees.first.events_count).to eq(10)
        expect(fees.first.amount_cents).to eq(30_000) # 30 units * 10 amount * 100 cents
        expect(fees.first.grouped_by).to eq({})
      end
    end
  end
end
