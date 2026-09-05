# frozen_string_literal: true

require "rails_helper"

RSpec.describe CatalogPlans::UpdateService do
  subject(:result) { described_class.call(catalog_plan:, params:) }

  let(:catalog_plan) { create(:catalog_plan, name: "Before", code: "before") }
  let(:params) { {name: "After", code: "after"} }

  it "updates the catalog plan" do
    expect(result).to be_success
    expect(result.catalog_plan.reload).to have_attributes(name: "After", code: "after")
  end

  context "when the catalog plan is missing" do
    let(:catalog_plan) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end

  context "when the update is invalid" do
    let(:params) { {currency: "INVALID"} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ValidationFailure)
    end
  end
end
