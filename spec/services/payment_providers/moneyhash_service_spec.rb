# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::MoneyhashService do
  let(:organization) { create(:organization) }
  let(:moneyhash_provider) { create(:moneyhash_provider, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:moneyhash_customer) { create(:moneyhash_customer, customer:) }

  describe "#create_or_update" do
    let(:webhook_signature_response) { JSON.parse(File.read(Rails.root.join("spec/fixtures/moneyhash/webhook_signature_response.json"))) }

    before do
      allow_any_instance_of(LagoHttpClient::Client).to receive(:get).and_return(webhook_signature_response) # rubocop:disable RSpec/AnyInstance
    end

    it "creates a new moneyhash provider with the webhook signature key" do
      result = described_class.new.create_or_update(organization:, code: "test_code", name: "test_name", flow_id: "test_flow_id")
      expect(result).to be_success
      expect(result.moneyhash_provider).to be_a(PaymentProviders::MoneyhashProvider)
      expect(result.moneyhash_provider.signature_key).to eq(webhook_signature_response.dig("data", "webhook_signature_secret"))
      expect(result.moneyhash_provider.code).to eq("test_code")
      expect(result.moneyhash_provider.name).to eq("test_name")
      expect(result.moneyhash_provider.flow_id).to eq("test_flow_id")
    end

    it "updates the existing moneyhash provider but leaves the signature key unchanged" do
      moneyhash_provider.update!(signature_key: "same_signature_key")
      result = described_class.new.create_or_update(organization:, code: moneyhash_provider.code, name: "updated_name", flow_id: "updated_flow_id")
      expect(result).to be_success
      expect(result.moneyhash_provider).to be_a(PaymentProviders::MoneyhashProvider)
      expect(result.moneyhash_provider.signature_key).to eq("same_signature_key")
      expect(result.moneyhash_provider.code).to eq(moneyhash_provider.code)
      expect(result.moneyhash_provider.name).to eq("updated_name")
      expect(result.moneyhash_provider.flow_id).to eq("updated_flow_id")
    end
  end

  # Intent
  # handle event - intent.processed <-
  # handle event - intent.time_expired <-
  describe "#handle_intent_event" do
    let(:intent_processed_event_json) { JSON.parse(File.read(Rails.root.join("spec/fixtures/moneyhash/intent.processed.json"))) }
    let(:intent_time_expired_event_json) { JSON.parse(File.read(Rails.root.join("spec/fixtures/moneyhash/intent.time_expired.json"))) }

    # intent processed payment & invoice
    let(:payment_processed) { create(:payment, payment_provider: moneyhash_provider, provider_payment_id: intent_processed_event_json.dig("data", "intent_id"), payable: invoice_processed) }
    let(:invoice_processed) { create(:invoice, organization:, customer:) }

    # intent time expired payment & invoice
    let(:payment_time_expired) { create(:payment, payment_provider: moneyhash_provider, provider_payment_id: intent_time_expired_event_json.dig("data", "intent_id"), payable: invoice_time_expired) }
    let(:invoice_time_expired) { create(:invoice, organization:, customer:) }

    it "handles intent.processed event" do
      intent_processed_event_json["data"]["intent"]["custom_fields"]["lago_payable_type"] = "Invoice"
      intent_processed_event_json["data"]["intent"]["custom_fields"]["lago_payable_id"] = invoice_processed.id

      payment_processed
      result = described_class.new.handle_event(organization:, event_json: intent_processed_event_json)
      payment_processed.reload
      expect(result).to be_success
      expect(payment_processed.status).to eq("succeeded")
      expect(payment_processed.payable_payment_status).to eq("succeeded")
      expect(payment_processed.payable.payment_status).to eq("succeeded")
    end

    it "handles intent.time_expired event" do
      intent_time_expired_event_json["data"]["intent"]["custom_fields"]["lago_payable_type"] = "Invoice"
      intent_time_expired_event_json["data"]["intent"]["custom_fields"]["lago_payable_id"] = invoice_time_expired.id

      payment_time_expired
      result = described_class.new.handle_event(organization:, event_json: intent_time_expired_event_json)
      payment_time_expired.reload
      expect(result).to be_success
      expect(payment_time_expired.status).to eq("failed")
      expect(payment_time_expired.payable_payment_status).to eq("failed")
      expect(payment_time_expired.payable.payment_status).to eq("failed")
    end
  end

  # Transaction
  # handle event - transaction.purchase.successful <-
  # handle event - transaction.purchase.pending_authentication <-
  # handle event - transaction.purchase.failed <-
  describe "#handle_transaction_event" do
    let(:transaction_successful_event_json) { JSON.parse(File.read(Rails.root.join("spec/fixtures/moneyhash/transaction.purchase.successful.json"))) }
    let(:transaction_pending_authentication_event_json) { JSON.parse(File.read(Rails.root.join("spec/fixtures/moneyhash/transaction.purchase.pending_authentication.json"))) }
    let(:transaction_failed_event_json) { JSON.parse(File.read(Rails.root.join("spec/fixtures/moneyhash/transaction.purchase.failed.json"))) }

    # transaction successful payment & invoice
    let(:payment) { create(:payment, payment_provider: moneyhash_provider, provider_payment_id: transaction_successful_event_json.dig("intent", "id"), payable: invoice) }
    let(:invoice) { create(:invoice, organization:, customer:) }

    # transaction pending authentication payment & invoice
    let(:payment_pending_authentication) { create(:payment, payment_provider: moneyhash_provider, provider_payment_id: transaction_pending_authentication_event_json.dig("intent", "id"), payable: invoice_pending_authentication) }
    let(:invoice_pending_authentication) { create(:invoice, organization:, customer:) }

    # transaction failed payment & invoice
    let(:payment_failed) { create(:payment, payment_provider: moneyhash_provider, provider_payment_id: transaction_failed_event_json.dig("intent", "id"), payable: invoice_failed) }
    let(:invoice_failed) { create(:invoice, organization:, customer:) }

    before do
      moneyhash_provider
      moneyhash_customer
      payment
      payment_pending_authentication
      payment_failed

      transaction_successful_event_json["intent"]["custom_fields"]["lago_payable_type"] = "Invoice"
      transaction_successful_event_json["intent"]["custom_fields"]["lago_payable_id"] = invoice.id
      transaction_successful_event_json["intent"]["custom_fields"]["lago_customer_id"] = moneyhash_customer.customer_id

      transaction_pending_authentication_event_json["intent"]["custom_fields"]["lago_payable_type"] = "Invoice"
      transaction_pending_authentication_event_json["intent"]["custom_fields"]["lago_payable_id"] = invoice_pending_authentication.id
      transaction_pending_authentication_event_json["intent"]["custom_fields"]["lago_customer_id"] = moneyhash_customer.customer_id

      transaction_failed_event_json["intent"]["custom_fields"]["lago_payable_type"] = "Invoice"
      transaction_failed_event_json["intent"]["custom_fields"]["lago_payable_id"] = invoice_failed.id
      transaction_failed_event_json["intent"]["custom_fields"]["lago_customer_id"] = moneyhash_customer.customer_id
    end

    it "handles transaction.purchase.successful event" do
      result = described_class.new.handle_event(organization:, event_json: transaction_successful_event_json)
      payment.reload
      expect(result).to be_success
      expect(payment.status).to eq("succeeded")
      expect(payment.payable_payment_status).to eq("succeeded")
      expect(payment.payable.payment_status).to eq("succeeded")
    end

    it "handles transaction.purchase.pending_authentication event" do
      result = described_class.new.handle_event(organization:, event_json: transaction_pending_authentication_event_json)
      payment_pending_authentication.reload
      expect(result).to be_success
      expect(payment_pending_authentication.status).to eq("processing")
      expect(payment_pending_authentication.payable_payment_status).to eq("pending")
      expect(payment_pending_authentication.payable.payment_status).to eq("pending")
    end

    it "handles transaction.purchase.failed event" do
      result = described_class.new.handle_event(organization:, event_json: transaction_failed_event_json)
      payment_failed.reload
      expect(result).to be_success
      expect(payment_failed.status).to eq("failed")
      expect(payment_failed.payable_payment_status).to eq("failed")
      expect(payment_failed.payable.payment_status).to eq("failed")
    end
  end

  # Card Token
  # handle event - card_token.created <-
  # handle event - card_token.updated <-
  # handle event - card_token.deleted <-
  describe "#handle_card_event" do
    before do
      moneyhash_provider
      moneyhash_customer
    end

    it "handles card_token.created event" do
      card_token_created_event_json = JSON.parse(File.read(Rails.root.join("spec/fixtures/moneyhash/card_token.created.json")))
      card_token_created_event_json["data"]["card_token"]["custom_fields"]["lago_customer_id"] = moneyhash_customer.customer_id

      result = described_class.new.handle_event(organization:, event_json: card_token_created_event_json)
      expect(result).to be_success
      moneyhash_customer.reload
      expect(moneyhash_customer.payment_method_id).to eq(card_token_created_event_json.dig("data", "card_token", "id"))
    end

    it "handles card_token.updated event" do
      card_token_updated_event_json = JSON.parse(File.read(Rails.root.join("spec/fixtures/moneyhash/card_token.updated.json")))
      card_token_updated_event_json["data"]["card_token"]["custom_fields"]["lago_customer_id"] = moneyhash_customer.customer_id

      result = described_class.new.handle_event(organization:, event_json: card_token_updated_event_json)
      expect(result).to be_success
      moneyhash_customer.reload
      expect(moneyhash_customer.payment_method_id).to eq(card_token_updated_event_json.dig("data", "card_token", "id"))
    end

    it "handles card_token.deleted event" do
      card_token_deleted_event_json = JSON.parse(File.read(Rails.root.join("spec/fixtures/moneyhash/card_token.deleted.json")))
      card_token_deleted_event_json["data"]["card_token"]["custom_fields"]["lago_customer_id"] = moneyhash_customer.customer_id
      moneyhash_customer.update!(payment_method_id: card_token_deleted_event_json.dig("data", "card_token", "id"))

      result = described_class.new.handle_event(organization:, event_json: card_token_deleted_event_json)
      expect(result).to be_success
      moneyhash_customer.reload
      expect(moneyhash_customer.payment_method_id).to be_nil
    end

    it "card_token.deleted event ignored if not the same card" do
      card_token_deleted_event_json = JSON.parse(File.read(Rails.root.join("spec/fixtures/moneyhash/card_token.deleted.json")))
      card_token_deleted_event_json["data"]["card_token"]["custom_fields"]["lago_customer_id"] = moneyhash_customer.customer_id
      moneyhash_customer.update!(payment_method_id: "test_payment_id")

      result = described_class.new.handle_event(organization:, event_json: card_token_deleted_event_json)
      expect(result).to be_success
      moneyhash_customer.reload
      expect(moneyhash_customer.payment_method_id).to eq("test_payment_id")
    end
  end
end
