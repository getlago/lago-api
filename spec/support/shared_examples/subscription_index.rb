# frozen_string_literal: true

RSpec.shared_examples "a subscription index endpoint" do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 500, description: "desc") }
  let!(:subscription) { create(:subscription, customer:, plan:) }
  let(:external_customer_id) { customer.external_id }
  let(:params) { {} }

  include_examples "requires API permission", "subscription", "read"

  it "returns subscriptions" do
    subject

    expect(response).to have_http_status(:success)
    expect(json[:subscriptions].count).to eq(1)
    expect(json[:subscriptions].first[:lago_id]).to eq(subscription.id)
  end

  context "with next and previous subscriptions" do
    let(:previous_subscription) do
      create(
        :subscription,
        customer:,
        plan: create(:plan, organization:),
        status: :terminated
      )
    end

    let(:next_subscription) do
      create(
        :subscription,
        customer:,
        plan: create(:plan, organization:),
        status: :pending
      )
    end

    before do
      subscription.update!(previous_subscription:, next_subscriptions: [next_subscription])
    end

    it "returns next and previous plan code" do
      subject

      subscription = json[:subscriptions].first
      expect(subscription[:previous_plan_code]).to eq(previous_subscription.plan.code)
      expect(subscription[:next_plan_code]).to eq(next_subscription.plan.code)
    end

    it "returns the downgrade plan date" do
      current_date = DateTime.parse("20 Jun 2022")

      travel_to(current_date) do
        subject

        subscription = json[:subscriptions].first
        expect(subscription[:downgrade_plan_date]).to eq("2022-07-01")
      end
    end
  end

  context "with pagination" do
    let(:params) do
      {
        page: 1,
        per_page: 1
      }
    end

    before do
      another_plan = create(:plan, organization:, amount_cents: 30_000)
      create(:subscription, customer:, plan: another_plan)
    end

    it "returns subscriptions with correct meta data" do
      subject

      expect(response).to have_http_status(:success)

      expect(json[:subscriptions].count).to eq(1)
      expect(json[:meta][:current_page]).to eq(1)
      expect(json[:meta][:next_page]).to eq(2)
      expect(json[:meta][:prev_page]).to eq(nil)
      expect(json[:meta][:total_pages]).to eq(2)
      expect(json[:meta][:total_count]).to eq(2)
    end
  end

  context "with plan code" do
    let(:params) { {plan_code: plan.code} }

    it "returns subscriptions" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:subscriptions].count).to eq(1)
      expect(json[:subscriptions].first[:lago_id]).to eq(subscription.id)
    end
  end

  context "with terminated status" do
    let!(:terminated_subscription) do
      create(:subscription, customer:, plan: create(:plan, organization:), status: :terminated)
    end

    let(:params) do
      {
        status: ["terminated"]
      }
    end

    it "returns terminated subscriptions" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:subscriptions].count).to eq(1)
      expect(json[:subscriptions].first[:lago_id]).to eq(terminated_subscription.id)
    end
  end
end
