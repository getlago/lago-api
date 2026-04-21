# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::CreateService do
  subject(:result) do
    described_class.call(
      organization:,
      customer:,
      subscription:,
      params:
    )
  end

  let(:organization) { create(:organization, feature_flags: ["quote"]) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { nil }
  let(:params) { {order_type: "one_off"} }

  context "when license is premium", :premium do
    it "creates a quote" do
      expect { result }.to change(Quote, :count).by(1)

      expect(result).to be_success
      quote = result.quote
      expect(quote.organization_id).to eq(organization.id)
      expect(quote.customer_id).to eq(customer.id)
      expect(quote.subscription_id).to be_nil
      expect(quote.order_type).to eq("one_off")
      expect(quote.status).to eq("draft")
      expect(quote.version).to eq(1)
      expect(quote.sequential_id).to eq(1)
      expect(quote.number).to match(/\AQT-\d{4}-\d{4}\z/)
    end

    context "with a subscription" do
      let(:subscription) { create(:subscription, organization:, customer:) }
      let(:params) { {order_type: "subscription_amendment"} }

      it "persists the subscription on the quote" do
        expect(result).to be_success
        expect(result.quote.subscription_id).to eq(subscription.id)
        expect(result.quote.order_type).to eq("subscription_amendment")
      end
    end

    context "with owners" do
      let(:owner_membership) { create(:membership, organization:) }
      let(:other_owner_membership) { create(:membership, organization:) }
      let(:params) do
        {
          order_type: "one_off",
          owners: [owner_membership.user_id, other_owner_membership.user_id]
        }
      end

      it "creates a quote_owner row for each owner" do
        expect { result }.to change(QuoteOwner, :count).by(2)

        expect(result).to be_success
        expect(result.quote.owners).to match_array([owner_membership.user, other_owner_membership.user])
      end
    end

    context "when an owner does not belong to the organization" do
      let(:owner_membership) { create(:membership, organization:) }
      let(:stranger) { create(:user) }
      let(:params) do
        {
          order_type: "one_off",
          owners: [owner_membership.user_id, stranger.id]
        }
      end

      it "returns a validation failure and rolls back" do
        expect { result }.not_to change(Quote, :count)
        expect { result }.not_to change(QuoteOwner, :count)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:owners]).to include("not_found")
      end
    end
  end

  context "when the quote feature flag is disabled", :premium do
    let(:organization) { create(:organization) }

    it "returns a forbidden failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
    end
  end

  context "when license is not premium" do
    it "returns a forbidden failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
    end
  end

  context "when organization is nil", :premium do
    let(:organization) { nil }
    let(:customer) { create(:customer) }

    it "returns a not_found failure for organization" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.error.resource).to eq("organization")
    end
  end

  context "when customer is nil", :premium do
    let(:customer) { nil }

    it "returns a not_found failure for customer" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
      expect(result.error.resource).to eq("customer")
    end
  end
end
