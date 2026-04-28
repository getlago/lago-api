# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::BillingItems::Plans::AddService, type: :service do
  subject(:result) { described_class.call(quote_version:, params:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:plan) { create(:plan, organization:) }
  let(:quote) { create(:quote, :with_version, organization:, order_type: :subscription_creation) }
  let(:quote_version) { quote.current_version }
  let(:params) { {plan_id: plan.id} }

  before { allow(License).to receive(:premium?).and_return(true) }

  it "adds the plan to billing_items and returns the quote_version" do
    expect(result).to be_success
    expect(result.quote_version.billing_items["plans"].length).to eq(1)
    expect(result.quote_version.billing_items["plans"].first["plan_id"]).to eq(plan.id)
    expect(result.quote_version.billing_items["plans"].first["id"]).to start_with("qtp_")
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

  context "when order_forms feature flag is disabled" do
    let(:organization) { create(:organization) }

    it "returns forbidden failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
    end
  end

  context "when quote_version is not draft" do
    let(:quote) { create(:quote, :with_version, organization:, order_type: :subscription_creation, version_trait: :approved) }

    it "returns not allowed failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotAllowedFailure)
    end
  end

  context "when order_type is one_off" do
    let(:quote) { create(:quote, :with_version, organization:, order_type: :one_off) }

    it "returns validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
    end
  end

  context "when plan_id is blank" do
    let(:params) { {} }

    it "returns validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
    end
  end

  context "when plan does not belong to organization" do
    let(:params) { {plan_id: create(:plan).id} }

    it "returns validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
    end
  end

  context "when a plan already exists in billing_items" do
    before { quote_version.update!(billing_items: {"plans" => [{"id" => "qtp_existing", "plan_id" => plan.id}]}) }

    it "appends the new plan" do
      expect(result).to be_success
      expect(result.quote_version.billing_items["plans"].length).to eq(2)
    end
  end
end
