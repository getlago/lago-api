# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261021110256_align_payment_receipt_api_key_permissions_with_invoice")

RSpec.describe AlignPaymentReceiptApiKeyPermissionsWithInvoice do
  describe "#up" do
    subject(:migrate) { described_class.new.up }

    let(:organization) { create(:organization) }
    let(:api_key) { create(:api_key, organization:, permissions:) }

    before { api_key }

    context "when the key has no payment_receipt permission" do
      let(:permissions) { {"invoice" => %w[read write], "customer" => %w[read]} }

      it "copies the invoice permission and keeps the others" do
        migrate

        expect(api_key.reload.permissions).to eq(
          "invoice" => %w[read write],
          "customer" => %w[read],
          "payment_receipt" => %w[read write]
        )
      end
    end

    context "when the payment_receipt permission is narrower than the invoice one" do
      let(:permissions) { {"invoice" => %w[read], "payment_receipt" => []} }

      it "copies the invoice permission" do
        migrate

        expect(api_key.reload.permissions).to eq("invoice" => %w[read], "payment_receipt" => %w[read])
      end
    end

    context "when the payment_receipt permission is wider than the invoice one" do
      let(:permissions) { {"invoice" => [], "payment_receipt" => %w[read write]} }

      it "copies the invoice permission" do
        migrate

        expect(api_key.reload.permissions).to eq("invoice" => [], "payment_receipt" => [])
      end
    end

    context "when the key has no invoice permission" do
      let(:permissions) { {"customer" => %w[read], "payment_receipt" => %w[read]} }

      it "removes the payment_receipt modes" do
        migrate

        expect(api_key.reload.permissions).to eq("customer" => %w[read], "payment_receipt" => [])
      end
    end

    context "when the key is expired" do
      let(:api_key) { create(:api_key, :expired, organization:, permissions:) }
      let(:permissions) { {"invoice" => %w[read]} }

      it "copies the invoice permission" do
        migrate

        expect(ApiKey.unscoped.find(api_key.id).permissions).to eq("invoice" => %w[read], "payment_receipt" => %w[read])
      end
    end

    context "when both permissions already match" do
      let(:permissions) { {"invoice" => %w[read], "payment_receipt" => %w[read]} }

      it "leaves the key untouched" do
        expect { migrate }.not_to change { api_key.reload.updated_at }
      end
    end
  end
end
