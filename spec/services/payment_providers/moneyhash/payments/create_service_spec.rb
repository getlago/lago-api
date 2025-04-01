# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Moneyhash::Payments::CreateService do
  let(:organization) { create(:organization) }
  let(:moneyhash_provider) { create(:moneyhash_provider, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:moneyhash_customer) { create(:moneyhash_customer, customer:, payment_provider: moneyhash_provider) }

  let(:reference) { "1234567890" }
  let(:metadata) { {} }

  let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :subscription) }
  let(:payment) { create(:payment, payable: invoice, payment_provider: moneyhash_provider, payment_provider_customer: moneyhash_customer) }

  let(:request_payload) { JSON.parse(File.read("spec/fixtures/moneyhash/recurring_mit_payment_payload.json")) }
  let(:failure_response) { JSON.parse(File.read("spec/fixtures/moneyhash/recurring_mit_payment_failure_response.json")) }
  let(:success_response) { JSON.parse(File.read("spec/fixtures/moneyhash/recurring_mit_payment_success_response.json")) }

  describe "#call" do
    it "succeeds for a successful payment of invoices" do
      allow_any_instance_of(described_class).to receive(:create_moneyhash_payment).and_return(success_response) # rubocop:disable RSpec/AnyInstance
      result = described_class.call(payment: payment, reference:, metadata:)
      expect(result).to be_success
      expect(result.payment.status).to eq("PROCESSED")
      expect(result.payment.provider_payment_id).to eq(success_response.dig("data", "id"))
      expect(result.payment.payable_payment_status).to eq("succeeded")
    end

    it "fails if error raised" do
      allow_any_instance_of(described_class).to receive(:moneyhash_payment_provider).and_return(moneyhash_provider) # rubocop:disable RSpec/AnyInstance
      allow_any_instance_of(LagoHttpClient::Client).to receive(:post_with_response).and_raise(LagoHttpClient::HttpError.new(400, failure_response, "")) # rubocop:disable RSpec/AnyInstance
      result = described_class.call(payment: payment, reference:, metadata:)
      expect(result).to be_failure
      expect(result.error_code).to eq(400)
      expect(result.error_message).to eq(failure_response)
      expect(payment.status).to eq("PENDING")
      expect(payment.payable_payment_status).to eq("processing")
    end
  end
end
