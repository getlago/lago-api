# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::PaymentMethodSerializer do
  subject(:result) { JSON.parse(described_class.new(payment_method, root_name: "payment_method").to_json)["payment_method"] }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:payment_method) { create(:payment_method, organization:, customer:, provider_method_id: "pm_123") }

  it "serializes the payment method" do
    expect(result).to eq(
      "lago_id" => payment_method.id,
      "lago_customer_id" => customer.id,
      "external_customer_id" => customer.external_id,
      "is_default" => true,
      "payment_provider_code" => payment_method.payment_provider.code,
      "payment_provider_name" => payment_method.payment_provider.name,
      "payment_provider_type" => payment_method.payment_provider_type,
      "provider_method_id" => "pm_123",
      "created_at" => payment_method.created_at.iso8601,
      "updated_at" => payment_method.updated_at.iso8601,
      "deleted_at" => nil
    )
  end

  context "when the payment method is deleted" do
    before { payment_method.discard! }

    it "renders the deletion time" do
      expect(result["deleted_at"]).to eq(payment_method.deleted_at.iso8601)
    end
  end
end
