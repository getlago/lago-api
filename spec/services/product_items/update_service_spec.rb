# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductItems::UpdateService do
  subject(:result) { described_class.call(product_item:, params:) }

  let(:organization) { create(:organization) }
  let(:product_item) { create(:product_item, organization:, name: "Before", code: "before") }

  let(:params) { {name: "After", description: "new", invoice_display_name: "Display"} }

  it "updates the mutable attributes" do
    expect(result).to be_success
    expect(result.product_item.name).to eq("After")
    expect(result.product_item.description).to eq("new")
    expect(result.product_item.invoice_display_name).to eq("Display")
  end

  it "does not change the code" do
    expect { result }.not_to change { product_item.reload.code }
  end

  it "produces an activity log" do
    result
    expect(Utils::ActivityLog).to have_produced("product_item.updated").after_commit.with(product_item)
  end

  context "when product_item is nil" do
    let(:product_item) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("product_item")
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
