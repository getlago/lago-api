# frozen_string_literal: true

require "rails_helper"

describe "Daily Usages: Fill History - Multiple Scenarios", :time_travel, :scenarios, type: :request, transaction: false do
  around { |test| lago_premium!(&test) }

  # Shared setup
  let(:organization) { create(:organization, webhook_url: nil, email_settings: [], premium_integrations: ["revenue_analytics"]) }
  let(:plan) { create(:plan, organization:, interval: "monthly", amount_cents: 0, pay_in_advance: true) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { customer.subscriptions.first }

  dates = {
    apr_29: DateTime.new(2025, 4, 29, 11, 0),
    apr_30: DateTime.new(2025, 4, 30, 11, 0),
    may_01: DateTime.new(2025, 5, 1, 11, 0),
    may_02: DateTime.new(2025, 5, 2, 11, 0),
    may_30: DateTime.new(2025, 5, 30, 11, 0),
    may_31: DateTime.new(2025, 5, 31, 11, 0),
    jun_01: DateTime.new(2025, 6, 1, 11, 0),
    jun_02: DateTime.new(2025, 6, 2, 11, 0),
    jun_29: DateTime.new(2025, 6, 29, 11, 0),
    jun_30: DateTime.new(2025, 6, 30, 11, 0),
    jul_01: DateTime.new(2025, 7, 1, 11, 0),
    jul_02: DateTime.new(2025, 7, 2, 11, 0)
  }

  context "when billable_metric.recurring is true" do
    let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: true) }



    context "when pay_in_advance is true" do
      context "when prorated is true" do
        let(:charge) { create(:standard_charge, billable_metric:, plan:, pay_in_advance: true, prorated: true, properties: {amount: "1"}) }

        before { charge }

        context "when customer is in UTC timezone" do
          it "fills daily usage history correctly" do
            # Expected values for each date
            expected_values = {
              apr_29: {usage: 2966.67, usage_diff: 100},
              apr_30: {usage: 3100, usage_diff: 100},
              may_01: {usage: 100, usage_diff: 100},
              may_02: {usage: 200, usage_diff: 100},
              may_30: {usage: 300, usage_diff: 100},
              may_31: {usage: 3100, usage_diff: 100},
              jun_01: {usage: 103.33, usage_diff: 103.33},
              jun_02: {usage: 206.66, usage_diff: 103.33},
              jun_29: {usage: 2966.67, usage_diff: 103.33},
              jun_30: {usage: 3100, usage_diff: 103.33},
              jul_01: {usage: 100, usage_diff: 100},
              jul_02: {usage: 200, usage_diff: 100}
            }

            travel_to(dates[:apr_29]) do
              create_subscription(
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan.code,
                billing_time: "anniversary"
              )
            end

            (dates[:apr_29]..dates[:jul_02]).each do |date|
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

            DailyUsages::FillHistoryService.call!(subscription:, from_datetime: dates[:apr_29], to_datetime: dates[:jul_02])
            expect(DailyUsage.count).to eq(65)

            daily_usages = dates.transform_values { |date| DailyUsage.find_by(usage_date: date.to_date) }

            expected_values.each do |date_key, expected|
              usage = daily_usages[date_key]
              expect(usage.usage["amount_cents"]).to eq(expected[:usage])
              expect(usage.usage_diff["amount_cents"]).to eq(expected[:usage_diff])
            end
          end
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

      # context "when prorated is false" do
      #   let(:charge) { create(:standard_charge, billable_metric:, plan:, pay_in_advance: true, prorated: false, properties: {amount: "1"}) }

      #   context "when customer is in UTC timezone" do
      #     it_behaves_like "fills daily usage history correctly"
      #   end

      #   # context "when customer is in UTC+ timezone" do
      #   #   let(:customer) { create(:customer, organization:, timezone: "Asia/Tokyo") }
      #   #   it_behaves_like "fills daily usage history correctly"
      #   # end

      #   # context "when customer is in UTC- timezone" do
      #   #   let(:customer) { create(:customer, organization:, timezone: "America/Los_Angeles") }
      #   #   it_behaves_like "fills daily usage history correctly"
      #   # end
      # end
    end

    # context "when pay_in_advance is false" do
    #   context "when prorated is false" do
    #     let(:charge) { create(:standard_charge, billable_metric:, plan:, pay_in_advance: false, prorated: false, properties: {amount: "1"}) }

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
    # end
  end

  context "when billable_metric.recurring is false" do
    let(:billable_metric) { create(:sum_billable_metric, organization:, recurring: false) }

    # # Note: prorated: true is invalid with recurring: false + pay_in_advance: true
    # context "when prorated is false" do
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
