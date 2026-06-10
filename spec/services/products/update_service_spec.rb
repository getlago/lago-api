# frozen_string_literal: true

require "rails_helper"

RSpec.describe Products::UpdateService do
  subject(:result) { described_class.call(product:, params:) }

  let(:organization) { create(:organization) }
  let(:product) { create(:product, organization:, name: "Before", code: "before") }

  let(:params) { {name: "After", description: "new", invoice_display_name: "Display"} }

  it "updates the mutable attributes" do
    expect(result).to be_success
    expect(result.product.name).to eq("After")
    expect(result.product.description).to eq("new")
    expect(result.product.invoice_display_name).to eq("Display")
  end

  it "does not change the code" do
    expect { result }.not_to change { product.reload.code }
  end

  it "produces an activity log" do
    result
    expect(Utils::ActivityLog).to have_produced("product.updated").after_commit.with(product)
  end

  context "when product is nil" do
    let(:product) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product")
    end
  end

  context "when name is blank" do
    let(:params) { {name: ""} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:name]).to be_present
    end
  end
end
