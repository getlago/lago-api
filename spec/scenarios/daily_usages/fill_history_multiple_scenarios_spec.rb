# frozen_string_literal: true

require "rails_helper"

describe "Daily Usages: Fill History - Multiple Scenarios", :time_travel, :scenarios, type: :request, transaction: false do
  around { |test| lago_premium!(&test) }

  # Shared setup
  let(:organization) { create(:organization, webhook_url: nil, email_settings: [], premium_integrations: ["revenue_analytics"]) }
  let(:plan) { create(:plan, organization:, interval: "monthly", amount_cents: 0, pay_in_advance: true) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { customer.subscriptions.first }

  before { charge }

  # Shared test logic
  shared_examples "fills daily usage history correctly" do |expected_values|
    it "fills daily usage history" do
      mar_18 = DateTime.new(2025, 3, 18, 11, 0)
      mar_19 = DateTime.new(2025, 3, 19, 11, 0)

      apr_16 = DateTime.new(2025, 4, 16, 11, 0)
      apr_17 = DateTime.new(2025, 4, 17, 11, 0)
      apr_18 = DateTime.new(2025, 4, 18, 11, 0)
      apr_19 = DateTime.new(2025, 4, 19, 11, 0)
      apr_20 = DateTime.new(2025, 4, 20, 11, 0)
      may_18 = DateTime.new(2025, 5, 18, 11, 0)

      travel_to(mar_18) do
        create_subscription(
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code,
          billing_time: "anniversary"
        )
      end

      (mar_18..apr_18).each do |date|
        travel_to(date) do
          create_event(
            {
              code: billable_metric.code,
              transaction_id: SecureRandom.uuid,
              external_subscription_id: subscription.external_id,
              properties: {"item_id" => 1}
            }
          )
        end
      end

      travel_back

      DailyUsages::FillHistoryService.call!(subscription:, from_datetime: mar_18, to_datetime: apr_20)

      expect(DailyUsage.count).to eq(33) # 33 days from mar_19 to apr_20

      first_daily_usage = DailyUsage.find_by(usage_date: mar_18.to_date)
      second_daily_usage = DailyUsage.find_by(usage_date: mar_19.to_date)

      second_last_daily_usage = DailyUsage.find_by(usage_date: apr_16.to_date)
      last_daily_usage = DailyUsage.find_by(usage_date: apr_17.to_date)

      first_next_period_daily_usage = DailyUsage.find_by(usage_date: apr_18.to_date)
      second_next_period_daily_usage = DailyUsage.find_by(usage_date: apr_19.to_date)

      expect(first_daily_usage.usage["amount_cents"]).to eq(expected_values[:first_usage])
      expect(first_daily_usage.usage_diff["amount_cents"]).to eq(expected_values[:first_usage_diff])
      expect(first_daily_usage.usage_date).to eq(mar_18.to_date)
      expect(first_daily_usage.from_datetime).to eq(mar_18)
      expect(first_daily_usage.to_datetime).to eq(apr_18.to_date - 1.second)

      expect(second_daily_usage.usage["amount_cents"]).to eq(expected_values[:second_usage])
      expect(second_daily_usage.usage_diff["amount_cents"]).to eq(expected_values[:second_usage_diff])
      expect(second_daily_usage.usage_date).to eq(mar_19.to_date)
      expect(second_daily_usage.from_datetime).to eq(mar_18)
      expect(second_daily_usage.to_datetime).to eq(apr_18.to_date - 1.second)

      expect(second_last_daily_usage.usage["amount_cents"]).to eq(expected_values[:second_last_usage])
      expect(second_last_daily_usage.usage_diff["amount_cents"]).to eq(expected_values[:second_last_usage_diff])
      expect(second_last_daily_usage.usage_date).to eq(apr_16.to_date)
      expect(second_last_daily_usage.from_datetime).to eq(mar_18)
      expect(second_last_daily_usage.to_datetime).to eq(apr_18.to_date - 1.second)

      expect(last_daily_usage.usage["amount_cents"]).to eq(expected_values[:last_usage])
      expect(last_daily_usage.usage_diff["amount_cents"]).to eq(expected_values[:last_usage_diff])
      expect(last_daily_usage.usage_date).to eq(apr_17.to_date)
      expect(last_daily_usage.from_datetime).to eq(mar_18)
      expect(last_daily_usage.to_datetime).to eq(apr_18.to_date - 1.second)

      expect(first_next_period_daily_usage.usage["amount_cents"]).to eq(expected_values[:first_next_period_usage])
      expect(first_next_period_daily_usage.usage_diff["amount_cents"]).to eq(expected_values[:first_next_period_usage_diff])
      expect(first_next_period_daily_usage.usage_date).to eq(apr_18.to_date)
      expect(first_next_period_daily_usage.from_datetime).to eq(apr_18.beginning_of_day)
      expect(first_next_period_daily_usage.to_datetime).to eq(may_18.to_date - 1.second)

      expect(second_next_period_daily_usage.usage["amount_cents"]).to eq(expected_values[:second_next_period_usage])
      expect(second_next_period_daily_usage.usage_diff["amount_cents"]).to eq(expected_values[:second_next_period_usage_diff])
      expect(second_next_period_daily_usage.usage_date).to eq(apr_19.to_date)
      expect(second_next_period_daily_usage.from_datetime).to eq(apr_18.beginning_of_day)
      expect(second_next_period_daily_usage.to_datetime).to eq(may_18.to_date - 1.second)
    end
  end

  context "when billable_metric.recurring is true" do
    let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }

    context "when pay_in_advance is true" do
      context "when prorated is true" do
        let(:charge) { create(:standard_charge, billable_metric:, plan:, pay_in_advance: true, prorated: true, properties: {amount: "1"}) }

        context "when customer is in UTC timezone" do
          it_behaves_like "fills daily usage history correctly", {
            bp1_first_day_usage: 100,
            bp1_first_day_usage_diff: 100,
            bp1_second_day_usage: 197,
            bp1_second_day_usage_diff: 97,
            bp1_second_last_day_usage: 1597,
            bp1_second_last_day_usage_diff: 7,
            bp1_last_day_usage: 1600,
            bp1_last_day_usage_diff: 3,
            bp2_first_day_usage: 100,
            bp2_first_day_usage_diff: 100,
            bp2_second_day_usage: 197,
            bp2_second_day_usage_diff: 97,
            bp2_second_last_day_usage: 1597,
            bp2_second_last_day_usage_diff: 7,
            bp2_last_day_usage: 1600,
            bp2_last_day_usage_diff: 3,
            bp3_first_day_usage: 100,
            bp3_first_day_usage_diff: 100,
            bp3_second_day_usage: 197,
            bp3_second_day_usage_diff: 97,
            bp1_second_last_day_usage: 1597,
            bp1_second_last_day_usage_diff: 7,
            bp1_last_day_usage: 1600,
            bp1_last_day_usage_diff: 3,
          }
        end

        # context "when customer is in UTC+ timezone" do
        #   let(:customer) { create(:customer, organization:, timezone: "Asia/Tokyo") }
        #   it_behaves_like "fills daily usage history correctly"
        # end

        # context "when customer is in UTC- timezone" do
        #   let(:customer) { create(:customer, organization:, timezone: "America/Los_Angeles") }
        #   it_behaves_like "fills daily usage history correctly"
        # end
      end

  #     context "when prorated is false" do
  #       let(:charge) { create(:standard_charge, billable_metric:, plan:, pay_in_advance: true, prorated: false, properties: {amount: "1"}) }

  #       context "when customer is in UTC timezone" do
  #         it_behaves_like "fills daily usage history correctly"
  #       end

  #       # context "when customer is in UTC+ timezone" do
  #       #   let(:customer) { create(:customer, organization:, timezone: "Asia/Tokyo") }
  #       #   it_behaves_like "fills daily usage history correctly"
  #       # end

  #       # context "when customer is in UTC- timezone" do
  #       #   let(:customer) { create(:customer, organization:, timezone: "America/Los_Angeles") }
  #       #   it_behaves_like "fills daily usage history correctly"
  #       # end
  #     end
  #   end

  #   context "when pay_in_advance is false" do
  #     context "when prorated is false" do
  #       let(:charge) { create(:standard_charge, billable_metric:, plan:, pay_in_advance: false, prorated: false, properties: {amount: "1"}) }

  #       context "when customer is in UTC timezone" do
  #         it_behaves_like "fills daily usage history correctly"
  #       end

  #       # context "when customer is in UTC+ timezone" do
  #       #   let(:customer) { create(:customer, organization:, timezone: "Asia/Tokyo") }
  #       #   it_behaves_like "fills daily usage history correctly"
  #       # end

  #       # context "when customer is in UTC- timezone" do
  #       #   let(:customer) { create(:customer, organization:, timezone: "America/Los_Angeles") }
  #       #   it_behaves_like "fills daily usage history correctly"
  #       end
      end
    end

  # context "when billable_metric.recurring is false" do
  #   let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: false) }

  #   # Note: prorated: true is invalid with recurring: false + pay_in_advance: true
  #   context "when prorated is false" do
    #   context "when pay_in_advance is true" do
    #     let(:charge) { create(:standard_charge, billable_metric:, plan:, pay_in_advance: true, prorated: false, properties: {amount: "1"}) }

    #     context "when customer is in UTC timezone" do
    #       it_behaves_like "fills daily usage history correctly"
    #     end

    #     # context "when customer is in UTC+ timezone" do
    #     #   let(:customer) { create(:customer, organization:, timezone: "Asia/Tokyo") }
    #     #   it_behaves_like "fills daily usage history correctly"
    #     # end

    #     # context "when customer is in UTC- timezone" do
    #     #   let(:customer) { create(:customer, organization:, timezone: "America/Los_Angeles") }
    #     #   it_behaves_like "fills daily usage history correctly"
    #     # end
    #   end

    # context "when pay_in_advance is false" do
    #   context "when prorated is false" do
    #     let(:charge) { create(:standard_charge, billable_metric:, plan:, pay_in_advance: false, prorated: false, properties: {amount: "1"}) }

    #     context "when customer is in UTC timezone" do
    #       it_behaves_like "fills daily usage history correctly", {
    #         first_usage: 100,
    #         first_usage_diff: 100,
    #         second_usage: 200,
    #         second_usage_diff: 100,
    #         second_last_usage: 3100,
    #         second_last_usage_diff: 100,
    #         last_usage: 3200,
    #         last_usage_diff: 100,
    #         first_next_period_usage: 3200,
    #         first_next_period_usage_diff: 3200,
    #         second_next_period_usage: 3200,
    #         second_next_period_usage_diff: 0
    #       }
    #     end

    #     # context "when customer is in UTC+ timezone" do
    #     #   let(:customer) { create(:customer, organization:, timezone: "Asia/Tokyo") }
    #     #   it_behaves_like "fills daily usage history correctly"
    #     # end

    #     # context "when customer is in UTC- timezone" do
    #     #   let(:customer) { create(:customer, organization:, timezone: "America/Los_Angeles") }
    #     #   it_behaves_like "fills daily usage history correctly"
    #     # end
    #   end
    # end
  end
end
