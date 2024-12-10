# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionsQuery, type: :query do
  subject(:result) { described_class.call(organization:, pagination:, filters:) }

  let(:returned_ids) { result.subscriptions.pluck(:id) }

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:filters) { {} }

  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }

  before { subscription }

  it "returns a list of subscriptions" do
    expect(result).to be_success
    expect(result.subscriptions.count).to eq(1)
    expect(result.subscriptions).to eq([subscription])
  end

  context "when subscriptions have the same values for the ordering criteria" do
    let(:subscription) { create(:subscription, customer:, plan:, started_at: 1.day.ago) }
    let(:subscription_2) do
      create(
        :subscription,
        customer:,
        plan:,
        started_at: subscription.started_at,
        created_at: subscription.created_at
      ).tap do |subs|
        subs.update! id: "00000000-0000-0000-0000-000000000000"
      end
    end

    before { subscription_2 }

    it "returns a consistent list" do
      expect(result).to be_success
      expect(returned_ids).to eq([subscription_2.id, subscription.id])
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 2, limit: 10} }

    it "applies the pagination" do
      expect(result).to be_success
      expect(result.subscriptions.count).to eq(0)
      expect(result.subscriptions.current_page).to eq(2)
    end
  end

  context "with customer filter" do
    let(:filters) { {external_customer_id: customer.external_id} }

    it "applies the filter" do
      expect(result).to be_success
      expect(result.subscriptions.count).to eq(1)
    end
  end

  context "with plan filter" do
    let(:filters) { {plan_code: plan.code} }

    it "applies the filter" do
      expect(result).to be_success
      expect(result.subscriptions.count).to eq(1)
    end
  end

  context "with multiple status filter" do
    let(:filters) { {status: [:active, :pending]} }

    it "returns correct subscriptions" do
      create(:subscription, :pending, customer:, plan:)
      create(:subscription, customer:, plan:, status: :canceled)
      create(:subscription, customer:, plan:, status: :terminated)

      expect(result).to be_success
      expect(result.subscriptions.count).to eq(2)
      expect(result.subscriptions.active.count).to eq(1)
      expect(result.subscriptions.pending.count).to eq(1)
      expect(result.subscriptions.canceled.count).to eq(0)
      expect(result.subscriptions.terminated.count).to eq(0)
    end
  end

  context "with pending status filter" do
    let(:filters) { {status: [:pending]} }

    let(:subscription_1) do
      create(:subscription, :pending, customer:, plan:, created_at: Time.zone.parse("2024-10-12T00:01:01"))
    end

    let(:subscription_2) do
      create(:subscription, :pending, customer:, plan:, created_at: Time.zone.parse("2024-10-10T00:01:01"))
    end

    it "returns only pending subscriptions" do
      subscription_1
      subscription_2
      create(:subscription, customer:, plan:, status: :canceled)
      create(:subscription, customer:, plan:, status: :terminated)

      expect(result).to be_success
      expect(result.subscriptions.count).to eq(2)
      expect(result.subscriptions.active.count).to eq(0)
      expect(result.subscriptions.pending.count).to eq(2)
      expect(result.subscriptions.canceled.count).to eq(0)
      expect(result.subscriptions.terminated.count).to eq(0)
      expect(result.subscriptions.first).to eq(subscription_1)
    end
  end

  context "with canceled status filter" do
    let(:filters) { {status: [:canceled]} }

    it "returns only pending subscriptions" do
      create(:subscription, :pending, customer:, plan:)
      create(:subscription, customer:, plan:, status: :canceled)
      create(:subscription, customer:, plan:, status: :terminated)

      expect(result).to be_success
      expect(result.subscriptions.count).to eq(1)
      expect(result.subscriptions.active.count).to eq(0)
      expect(result.subscriptions.pending.count).to eq(0)
      expect(result.subscriptions.canceled.count).to eq(1)
      expect(result.subscriptions.terminated.count).to eq(0)
    end
  end

  context "with terminated status filter" do
    let(:filters) { {status: [:terminated]} }

    it "returns only pending subscriptions" do
      create(:subscription, :pending, customer:, plan:)
      create(:subscription, customer:, plan:, status: :canceled)
      create(:subscription, customer:, plan:, status: :terminated)

      expect(result).to be_success
      expect(result.subscriptions.count).to eq(1)
      expect(result.subscriptions.active.count).to eq(0)
      expect(result.subscriptions.pending.count).to eq(0)
      expect(result.subscriptions.canceled.count).to eq(0)
      expect(result.subscriptions.terminated.count).to eq(1)
    end
  end

  context "with no status filter" do
    it "returns only active subscriptions" do
      create(:subscription, :pending, customer:, plan:)

      expect(result).to be_success
      expect(result.subscriptions.count).to eq(1)
      expect(result.subscriptions.active.count).to eq(1)
      expect(result.subscriptions.pending.count).to eq(0)
      expect(result.subscriptions.canceled.count).to eq(0)
      expect(result.subscriptions.terminated.count).to eq(0)
    end
  end
end
