# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionsQuery, type: :query do
  subject(:result) { described_class.call(organization:, pagination:, filters:, search_term:) }

  let(:returned_ids) { result.subscriptions.pluck(:id) }

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:filters) { {} }
  let(:search_term) { nil }

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
        id: "00000000-0000-0000-0000-000000000000",
        started_at: subscription.started_at,
        created_at: subscription.created_at
      )
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

  context "with search_term" do
    let(:subscription) { create(:subscription, customer:, plan:, name: "Test Subscription") }
    let(:subscription_2) { create(:subscription, customer:, plan:, name: "Test Subscription 2") }

    before { subscription_2 }

    context "when search_term is an id" do
      let(:search_term) { subscription.id }

      it "returns only subscriptions for the specified id" do
        expect(result).to be_success
        expect(result.subscriptions.count).to eq(1)
        expect(result.subscriptions).to eq([subscription])
      end
    end

    context "when search_term is a name" do
      let(:search_term) { subscription_2.name }

      it "returns only subscriptions for the specified name" do
        expect(result).to be_success
        expect(result.subscriptions.count).to eq(1)
        expect(result.subscriptions).to eq([subscription_2])
      end
    end

    context "when search_term is an external_id" do
      let(:search_term) { subscription.external_id }

      it "returns only subscriptions for the specified external_id" do
        expect(result).to be_success
        expect(result.subscriptions.count).to eq(1)
        expect(result.subscriptions).to eq([subscription])
      end
    end

    context "when search_term is a customer name" do
      let(:search_term) { customer.name }

      it "returns only subscriptions for the specified customer name" do
        expect(result).to be_success
        expect(result.subscriptions.count).to eq(2)
        expect(result.subscriptions).to match_array([subscription, subscription_2])
      end
    end

    context "when search_term is a customer firstname" do
      let(:search_term) { customer.firstname }

      it "returns only subscriptions for the specified customer firstname" do
        expect(result).to be_success
        expect(result.subscriptions.count).to eq(2)
        expect(result.subscriptions).to match_array([subscription, subscription_2])
      end
    end

    context "when search_term is a customer lastname" do
      let(:search_term) { customer.lastname }

      it "returns only subscriptions for the specified customer lastname" do
        expect(result).to be_success
        expect(result.subscriptions.count).to eq(2)
        expect(result.subscriptions).to match_array([subscription, subscription_2])
      end
    end

    context "when search_term is a customer external_id" do
      let(:search_term) { customer.external_id }

      it "returns only subscriptions for the specified customer external_id" do
        expect(result).to be_success
        expect(result.subscriptions.count).to eq(2)
        expect(result.subscriptions).to match_array([subscription, subscription_2])
      end
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
      expect(result.subscriptions.first).to eq(subscription_2) # sorted by subscription_at DESC
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
    it "returns all subscriptions" do
      subscription_2 = create(:subscription, customer:, plan:, status: :terminated)
      subscription_3 = create(:subscription, customer:, plan:, status: :canceled)
      subscription_4 = create(:subscription, customer:, plan:, status: :pending)

      expect(result).to be_success
      expect(result.subscriptions.count).to eq(4)
      expect(result.subscriptions.active.count).to eq(1)
      expect(result.subscriptions.pending.count).to eq(1)
      expect(result.subscriptions.canceled.count).to eq(1)
      expect(result.subscriptions.terminated.count).to eq(1)
      expect(result.subscriptions).to match_array([subscription, subscription_2, subscription_3, subscription_4])
    end
  end

  context "with overriden filter" do
    let(:filters) { {} }
    let(:plan) { create(:plan, organization:, parent: parent_plan) }
    let(:parent_plan) { create(:plan, organization:) }
    let(:subscription) { create(:subscription, customer:, plan:) }
    let(:subscription_2) { create(:subscription, customer:, plan: parent_plan) }

    before { [subscription, subscription_2] }

    context "when overriden is true" do
      let(:filters) { {overriden: true} }

      it "returns only overriden subscriptions" do
        expect(result).to be_success
        expect(result.subscriptions.count).to eq(1)
        expect(result.subscriptions).to eq([subscription])
      end
    end

    context "when overriden is false" do
      let(:filters) { {overriden: false} }

      it "returns only non-overriden subscriptions" do
        expect(result).to be_success
        expect(result.subscriptions.count).to eq(1)
        expect(result.subscriptions).to eq([subscription_2])
      end
    end

    context "without overriden filter" do
      it "returns all subscriptions" do
        expect(result).to be_success
        expect(result.subscriptions.count).to eq(2)
        expect(result.subscriptions).to match_array([subscription, subscription_2])
      end
    end
  end

  context "with exclude_next_subscriptions filter" do
    let(:subscription) { create(:subscription, customer:, plan:, status: :active) }
    let(:next_subscription) { create(:subscription, previous_subscription: subscription, customer:, plan:, status: :pending) }
    let(:pending_subscription) { create(:subscription, :pending, customer:, plan:) }
    let(:terminated_subscription) { create(:subscription, :terminated, customer:, plan:) }

    before do
      subscription
      next_subscription
      pending_subscription
      terminated_subscription
    end

    context "when status filter is empty" do
      let(:filters) { {exclude_next_subscriptions: true, status: []} }

      it "returns only subscriptions without next subscription" do
        expect(result).to be_success
        expect(result.subscriptions.count).to eq(3)
        expect(result.subscriptions).to match_array([subscription, pending_subscription, terminated_subscription])
      end
    end

    context "when status filter is not empty" do
      context "when status filter matches previous subscription status" do
        let(:filters) { {exclude_next_subscriptions: true, status: [:active]} }

        it "returns only subscriptions without previous subscription" do
          expect(result).to be_success
          expect(result.subscriptions.count).to eq(1)
          expect(result.subscriptions).to eq([subscription])
        end
      end

      context "when status filter matches next subscription status" do
        let(:filters) { {exclude_next_subscriptions: true, status: [:pending]} }

        it "returns only subscriptions without next subscription" do
          expect(result).to be_success
          expect(result.subscriptions.count).to eq(2)
          expect(result.subscriptions).to match_array([pending_subscription, next_subscription])
        end
      end

      context "when status filter matches both previous and next subscription status" do
        let(:filters) { {exclude_next_subscriptions: true, status: [:pending, :active]} }

        it "returns only subscriptions without next subscription" do
          expect(result).to be_success
          expect(result.subscriptions.count).to eq(2)
          expect(result.subscriptions).to match_array([subscription, pending_subscription])
        end
      end

      context "when status filter does not match previous or next subscription status" do
        let(:filters) { {exclude_next_subscriptions: true, status: [:terminated]} }

        it "returns only subscriptions without next subscription" do
          expect(result).to be_success
          expect(result.subscriptions.count).to eq(1)
          expect(result.subscriptions).to eq([terminated_subscription])
        end
      end
    end

    context "when status filter contains multiple statuses" do
      let(:filters) { {exclude_next_subscriptions: true, status: [:pending, :active]} }

      let(:pending_without_previous) { create(:subscription, :pending, customer:, plan:) }
      let(:active_without_previous) { create(:subscription, :active, customer:, plan:) }
      let(:pending_with_terminated_previous) { create(:subscription, :pending, :with_previous_subscription, customer:, plan:) }
      let(:active_with_terminated_previous) { create(:subscription, :active, :with_previous_subscription, customer:, plan:) }
      let(:pending_with_pending_previous) { create(:subscription, :pending, :with_previous_subscription, customer:, plan:) }
      let(:subscription) { create(:subscription, :terminated, customer:, plan:) }

      before do
        pending_without_previous
        active_without_previous
        pending_with_terminated_previous.previous_subscription.update!(status: :terminated)
        active_with_terminated_previous.previous_subscription.update!(status: :terminated)
        pending_with_pending_previous.previous_subscription.update!(status: :pending)
      end

      it "returns subscriptions without previous OR with non-matching previous and matching current" do
        expect(result).to be_success
        expect(result.subscriptions.count).to eq(7)
        expect(result.subscriptions).to match_array([
          next_subscription,
          pending_subscription,
          pending_without_previous,
          active_without_previous,
          pending_with_terminated_previous,
          active_with_terminated_previous,
          pending_with_pending_previous.previous_subscription
        ])
      end

      it "excludes subscriptions with matching previous status" do
        expect(result.subscriptions).not_to include(pending_with_pending_previous)
      end
    end
  end
end
