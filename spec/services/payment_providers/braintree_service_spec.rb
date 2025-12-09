# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::BraintreeService do
  subject(:braintree_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:public_key) { "public_key" }
  let(:private_key) { "private_key" }
  let(:code) { "code_1" }
  let(:name) { "Name 1" }
  let(:merchant_id) { "lago_merchant" }
  let(:success_redirect_url) { Faker::Internet.url }

  describe ".create_or_update" do
    it "creates a braintree provider" do
      expect do
        braintree_service.create_or_update(
          organization:,
          public_key:,
          private_key:,
          code:,
          name:,
          merchant_id:,
          success_redirect_url:
        )
      end.to change(PaymentProviders::BraintreeProvider, :count).by(1)
    end

    context "when code was changed" do
      let(:new_code) { "updated_code_1" }
      let(:braintree_customer) { create(:braintree_customer, payment_provider:, customer:) }
      let(:customer) { create(:customer, organization:) }

      let(:payment_provider) do
        create(
          :braintree_provider,
          organization:,
          code:,
          name:,
          public_key: "public",
          private_key: "private",
          merchant_id: "merchant"
        )
      end

      before { braintree_customer }

      it "updates payment provider codes of all customers" do
        result = braintree_service.create_or_update(
          id: payment_provider.id,
          organization:,
          code: new_code,
          name:,
          public_key: "public",
          private_key: "private",
          merchant_id: "merchant"
        )

        aggregate_failures do
          expect(result).to be_success
          expect(result.braintree_provider.customers.first.payment_provider_code).to eq(new_code)
        end
      end
    end
  end
end
