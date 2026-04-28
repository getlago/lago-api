# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::Plans::RemoveService, type: :service do
  subject(:result) { described_class.call(quote_version:, id:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:plan) { create(:plan, organization:) }
  let(:item_id) { "qtp_#{SecureRandom.uuid}" }
  let(:quote) { create(:quote, :with_version, organization:, order_type: :subscription_creation) }
  let(:quote_version) { quote.current_version }
  let(:id) { item_id }

  before do
    allow(License).to receive(:premium?).and_return(true)
    quote_version.update!(billing_items: {"plans" => [{"id" => item_id, "plan_id" => plan.id}]})
  end

  it "removes the plan billing item" do
    expect(result).to be_success
    expect(result.quote_version.billing_items["plans"]).to be_empty
  end

  context "when not premium" do
    before { allow(License).to receive(:premium?).and_return(false) }

    it "returns forbidden failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
    end
  end

  context "when quote_version is nil" do
    let(:quote_version) { nil }

    it "returns not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "when quote_version is not draft" do
    let(:quote) { create(:quote, :with_version, organization:, order_type: :subscription_creation, version_trait: :approved) }

    it "returns not allowed failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotAllowedFailure)
    end
  end

  context "when item id is not found" do
    let(:id) { "qtp_nonexistent" }

    it "returns not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end
end
