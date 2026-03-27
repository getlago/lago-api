# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::UpdateService do
  subject(:update_service) { described_class.new(quote:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, :subscription_creation, customer:, organization:, description: "Original") }
  let(:params) { {description: "Updated"} }

  describe "#call" do
    it "updates the quote" do
      result = update_service.call

      expect(result).to be_success
      expect(result.quote.description).to eq("Updated")
    end

    it "only updates provided fields" do
      quote.update!(currency: "EUR")
      result = update_service.call

      expect(result.quote.currency).to eq("EUR")
      expect(result.quote.description).to eq("Updated")
    end

    context "with multiple fields" do
      let(:params) do
        {
          currency: "USD",
          description: "Updated quote",
          content: "New content",
          legal_text: "New legal",
          internal_notes: "New notes",
          commercial_terms: {"net_terms" => 30},
          contacts: [{"email" => "test@example.com"}],
          metadata: {"key" => "value"},
          auto_execute: true,
          execution_mode: "order_only",
          backdated_billing: "start_without_invoices"
        }
      end

      it "updates all provided fields" do
        result = update_service.call

        quote = result.quote
        expect(quote.currency).to eq("USD")
        expect(quote.description).to eq("Updated quote")
        expect(quote.content).to eq("New content")
        expect(quote.legal_text).to eq("New legal")
        expect(quote.internal_notes).to eq("New notes")
        expect(quote.commercial_terms).to eq({"net_terms" => 30})
        expect(quote.contacts).to eq([{"email" => "test@example.com"}])
        expect(quote.metadata).to eq({"key" => "value"})
        expect(quote.auto_execute).to be(true)
        expect(quote.execution_mode).to eq("order_only")
        expect(quote.backdated_billing).to eq("start_without_invoices")
      end
    end

    context "when quote is not draft" do
      let(:quote) { create(:quote, :subscription_creation, :approved, customer:, organization:) }

      it "returns not allowed failure" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("quote_not_draft")
      end
    end

    context "when quote is voided" do
      let(:quote) { create(:quote, :subscription_creation, :voided, customer:, organization:) }

      it "returns not allowed failure" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
      end
    end

    context "when quote is nil" do
      let(:quote) { nil }

      it "returns not found failure" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("quote")
      end
    end

    context "with billing_items update" do
      let(:params) do
        {
          billing_items: {
            "plan" => {"id" => SecureRandom.uuid, "position" => 1, "plan_id" => SecureRandom.uuid, "plan_name" => "New Plan"},
            "coupons" => [],
            "wallet_credits" => []
          }
        }
      end

      it "updates billing_items" do
        result = update_service.call

        expect(result).to be_success
        expect(result.quote.billing_items["plan"]).not_to be_empty
      end
    end

    context "with invalid billing_items for order_type" do
      let(:params) do
        {
          billing_items: {
            "add_ons" => [{"id" => SecureRandom.uuid, "position" => 1, "name" => "Setup", "add_on_id" => SecureRandom.uuid}]
          }
        }
      end

      it "returns validation failure" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:billing_items]).to include("add_ons_not_allowed_for_subscription")
      end

      it "does not update the quote" do
        update_service.call

        expect(quote.reload.billing_items).to be_nil
      end
    end

    context "with owner_ids" do
      let(:user) { membership.user }
      let(:other_user) { create(:membership, organization:).user }
      let(:params) { {owner_ids: [user.id, other_user.id]} }

      it "creates quote owners" do
        result = update_service.call

        expect(result).to be_success
        expect(result.quote.owners).to match_array([user, other_user])
      end

      context "when replacing existing owners" do
        before { create(:quote_owner, quote:, user:) }

        let(:params) { {owner_ids: [other_user.id]} }

        it "replaces all owners" do
          result = update_service.call

          expect(result).to be_success
          expect(result.quote.owners).to eq([other_user])
        end
      end
    end

    context "with empty owner_ids" do
      let(:user) { membership.user }
      let(:params) { {owner_ids: []} }

      before { create(:quote_owner, quote:, user:) }

      it "removes all owners" do
        result = update_service.call

        expect(result).to be_success
        expect(result.quote.owners).to be_empty
      end
    end

    context "with same owner_ids as existing" do
      let(:user) { membership.user }
      let(:other_user) { create(:membership, organization:).user }
      let(:params) { {owner_ids: [user.id, other_user.id]} }

      before do
        create(:quote_owner, quote:, user:)
        create(:quote_owner, quote:, user: other_user)
      end

      it "does not create duplicate owners" do
        result = update_service.call

        expect(result).to be_success
        expect(result.quote.owners).to match_array([user, other_user])
        expect(result.quote.quote_owners.count).to eq(2)
      end
    end

    context "with partial owner overlap" do
      let(:user) { membership.user }
      let(:other_user) { create(:membership, organization:).user }
      let(:new_user) { create(:membership, organization:).user }
      let(:params) { {owner_ids: [user.id, new_user.id]} }

      before do
        create(:quote_owner, quote:, user:)
        create(:quote_owner, quote:, user: other_user)
      end

      it "keeps existing, removes old, and adds new owners" do
        result = update_service.call

        expect(result).to be_success
        expect(result.quote.owners).to match_array([user, new_user])
      end
    end

    context "with owner from another organization" do
      let(:other_org_user) { create(:membership).user }
      let(:params) { {owner_ids: [other_org_user.id]} }

      it "silently ignores users from other organizations" do
        result = update_service.call

        expect(result).to be_success
        expect(result.quote.owners).to be_empty
      end
    end

    context "with non-existent owner_ids" do
      let(:params) { {owner_ids: [SecureRandom.uuid]} }

      it "silently ignores unknown user ids" do
        result = update_service.call

        expect(result).to be_success
        expect(result.quote.owners).to be_empty
      end
    end

    context "with non-array owner_ids" do
      let(:user) { membership.user }
      let(:params) { {owner_ids: "not_an_array"} }

      before { create(:quote_owner, quote:, user:) }

      it "does not remove existing owners" do
        result = update_service.call

        expect(result).to be_success
        expect(result.quote.owners).to match([user])
      end
    end

    context "when clearing billing_items" do
      let(:quote) do
        create(:quote, :subscription_creation, customer:, organization:, billing_items: {
          "plan" => {"id" => SecureRandom.uuid, "position" => 1, "plan_id" => SecureRandom.uuid, "plan_name" => "Plan"},
          "coupons" => [],
          "wallet_credits" => []
        })
      end
      let(:params) { {billing_items: nil} }

      it "allows setting billing_items to nil" do
        result = update_service.call

        expect(result).to be_success
        expect(result.quote.billing_items).to be_nil
      end
    end
  end
end
