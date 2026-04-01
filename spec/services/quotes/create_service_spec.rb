# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::CreateService do
  subject(:create_service) { described_class.new(organization:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:params) do
    {
      customer_id: customer.id,
      order_type: "subscription_creation",
      currency: "EUR",
      description: "Test quote"
    }
  end

  describe "#call" do
    it "creates a quote" do
      result = create_service.call

      expect(result).to be_success

      quote = result.quote
      expect(quote).to be_persisted
      expect(quote.organization).to eq(organization)
      expect(quote.customer).to eq(customer)
      expect(quote.order_type).to eq("subscription_creation")
      expect(quote.status).to eq("draft")
      expect(quote.version).to eq(1)
      expect(quote.currency).to eq("EUR")
      expect(quote.description).to eq("Test quote")
    end

    it "generates a number in QT-YYYY-NNNN format" do
      result = create_service.call

      expect(result.quote.number).to match(/\AQT-\d{4}-\d{4,}\z/)
    end

    it "generates a share_token" do
      result = create_service.call

      expect(result.quote.share_token).to be_present
      expect(result.quote.share_token.length).to eq(64)
    end

    context "with billing_items" do
      let(:plan_id) { SecureRandom.uuid }
      let(:params) do
        {
          customer_id: customer.id,
          order_type: "subscription_creation",
          billing_items: {
            "plan" => {"id" => SecureRandom.uuid, "position" => 1, "plan_id" => plan_id, "plan_name" => "Enterprise"},
            "coupons" => [],
            "wallet_credits" => []
          }
        }
      end

      it "stores billing_items on the quote" do
        result = create_service.call

        expect(result).to be_success
        expect(result.quote.billing_items["plan"]["plan_id"]).to eq(plan_id)
      end
    end

    context "with invalid billing_items for order_type" do
      let(:params) do
        {
          customer_id: customer.id,
          order_type: "subscription_creation",
          billing_items: {
            "plan" => {},
            "add_ons" => [{"id" => SecureRandom.uuid, "position" => 1, "name" => "Setup", "add_on_id" => SecureRandom.uuid}]
          }
        }
      end

      it "returns a validation failure" do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:billing_items]).to include("invalid_schema_at_add_ons")
      end

      it "does not create a quote" do
        expect { create_service.call }.not_to change(Quote, :count)
      end
    end

    context "with owner_ids" do
      let(:user) { membership.user }
      let(:params) do
        {
          customer_id: customer.id,
          order_type: "subscription_creation",
          owner_ids: [user.id]
        }
      end

      it "creates quote owners" do
        result = create_service.call

        expect(result).to be_success
        expect(result.quote.owners).to eq([user])
      end
    end

    context "with non-existent owner_id" do
      let(:params) do
        {
          customer_id: customer.id,
          order_type: "subscription_creation",
          owner_ids: [SecureRandom.uuid]
        }
      end

      it "silently skips unknown users" do
        result = create_service.call

        expect(result).to be_success
        expect(result.quote.owners).to be_empty
      end
    end

    context "when customer is not found" do
      let(:params) do
        {
          customer_id: SecureRandom.uuid,
          order_type: "subscription_creation"
        }
      end

      it "returns not found failure" do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("customer")
      end
    end

    context "with all optional fields" do
      let(:params) do
        {
          customer_id: customer.id,
          order_type: "one_off",
          currency: "USD",
          description: "Full quote",
          content: "Some content",
          legal_text: "Legal terms",
          internal_notes: "Internal note",
          billing_items: {"add_ons" => [{"id" => SecureRandom.uuid, "position" => 1, "add_on_id" => SecureRandom.uuid, "name" => "Setup", "amount_cents" => 100}]},
          commercial_terms: {"term_duration" => 12, "payment_terms" => "net_30"},
          contacts: [{"id" => SecureRandom.uuid, "name" => "John", "email" => "john@example.com", "position" => 1}],
          metadata: {"salesforce_id" => "123"},
          auto_execute: true,
          execution_mode: "execute_in_lago",
          backdated_billing: "generate_past_invoices"
        }
      end

      it "persists all fields" do
        result = create_service.call

        quote = result.quote
        expect(quote.currency).to eq("USD")
        expect(quote.content).to eq("Some content")
        expect(quote.legal_text).to eq("Legal terms")
        expect(quote.internal_notes).to eq("Internal note")
        expect(quote.billing_items["add_ons"].length).to eq(1)
        expect(quote.billing_items["add_ons"].first["name"]).to eq("Setup")
        expect(quote.commercial_terms).to eq({"term_duration" => 12, "payment_terms" => "net_30"})
        expect(quote.contacts).to eq([{"id" => params[:contacts].first["id"], "name" => "John", "email" => "john@example.com", "position" => 1}])
        expect(quote.metadata).to eq({"salesforce_id" => "123"})
        expect(quote.auto_execute).to be(true)
        expect(quote.execution_mode).to eq("execute_in_lago")
        expect(quote.backdated_billing).to eq("generate_past_invoices")
      end
    end
  end
end
