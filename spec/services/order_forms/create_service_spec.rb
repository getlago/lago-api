# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrderForms::CreateService do
  subject(:create_service) { described_class.new(organization:, customer:, params: create_params) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:create_params) {
    {
      auto_execute: true,
      backdated_billing: true,
      order_only: true
    }
  }

  describe ".call" do
    let(:result) { create_service.call }

    it "creates an empty draft order form" do
      travel_to(DateTime.new(2025, 3, 11, 20, 0, 0)) do
        expect(result).to be_success
        expect(result.order_form.organization.id).to eq(organization.id)
        expect(result.order_form.customer.id).to eq(customer.id)
        expect(result.order_form.version).to eq(1)
        expect(result.order_form.sequential_id).to eq(1)
        expect(result.order_form.number).to eq("OF-2025-0001")
        expect(result.order_form.draft?).to eq(true)
        expect(result.order_form.auto_execute).to eq(true)
        expect(result.order_form.backdated_billing).to eq(true)
        expect(result.order_form.order_only).to eq(true)
        expect(result.order_form.billing_payload).to eq({})
      end
    end
  end
end
