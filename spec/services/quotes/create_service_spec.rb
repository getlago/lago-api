# frozen_string_literal: true

require "rails_helper"

RSpec.describe Quotes::CreateService do
  subject(:create_service) do
    described_class.new(
      organization:,
      customer:,
      subscription:,
      params: create_params
    )
  end

  let_it_be(:organization) { create_default(:organization, feature_flags: ["order_forms"]) }
  let_it_be(:membership) { create_default(:membership, organization:) }
  let(:owner) { membership.user }
  let(:subscription) { nil }
  let(:create_params) do
    {
      billing_items: {},
      content: "Test content",
      order_type: :subscription_creation,
      owners: [owner.id]
    }
  end

  let_it_be(:customer) { create_default(:customer, organization:) }

  describe ".call" do
    let(:result) { create_service.call }

    context "when license is premium", :premium do
      it "creates an empty draft quote" do
        travel_to(DateTime.new(2025, 3, 11, 20, 0, 0)) do
          expect(result).to be_success
          expect(result.quote.organization_id).to eq(organization.id)
          expect(result.quote.customer_id).to eq(customer.id)
          expect(result.quote.sequential_id).to eq(1)
          expect(result.quote.number).to eq("QT-2025-0001")
          expect(result.quote.order_type).to eq("subscription_creation")
          expect(result.quote.owner_ids).to eq([owner.id])

          expect(result.quote.versions.size).to eq(1)
          expect(result.quote.current_version.version).to eq(1)
          expect(result.quote.current_version.draft?).to eq(true)
          expect(result.quote.current_version.content).to eq("Test content")
          expect(result.quote.current_version.billing_items).to eq({})
          expect(result.quote.current_version.currency).to eq("EUR")
        end
      end

      it "enqueues a quote.created webhook carrying the initial version" do
        expect { create_service.call }
          .to have_enqueued_job_after_commit(SendWebhookJob)
          .with("quote.created", QuoteVersion)
      end

      it "produces a quote.created activity log for the quote" do
        expect(Utils::ActivityLog).to have_produced("quote.created").after_commit.with(result.quote)
      end

      it "does not produce a quote.version_created activity log for the initial version" do
        result

        expect(Utils::ActivityLog).not_to have_produced("quote.version_created")
      end
    end

    context "when the customer has no currency", :premium do
      let(:customer) { create(:customer, organization:, currency: nil) }

      it "falls back to the billing entity default currency" do
        expect(result).to be_success
        expect(customer.billing_entity.default_currency).to eq("USD")
        expect(result.quote.current_version.currency).to eq("USD")
      end

      context "when the quote names another billing entity" do
        let(:billing_entity) { create(:billing_entity, organization:, default_currency: "EUR") }
        let(:create_params) { super().merge(billing_entity_id: billing_entity.id) }

        it "falls back to that entity's default currency" do
          expect(result).to be_success
          expect(result.quote.current_version.currency).to eq("EUR")
        end
      end
    end

    context "when the quote names a billing entity", :premium do
      let(:billing_entity) { create(:billing_entity, organization:) }
      let(:create_params) { super().merge(billing_entity_id: billing_entity.id) }

      it "pins it on the version" do
        expect(result).to be_success
        expect(result.quote.current_version.billing_entity_id).to eq(billing_entity.id)
      end
    end

    context "when the quote names an unknown billing entity", :premium do
      let(:create_params) { super().merge(billing_entity_id: "00000000-0000-0000-0000-000000000000") }

      it "returns a validation failure from the version validator" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages).to eq({billing_entity_id: ["billing_entity_not_found"]})
      end

      it "does not create the quote" do
        expect { result }.not_to change(Quote, :count)
      end
    end

    context "when the quote is one_off", :premium do
      let(:add_on) { create(:add_on, organization:) }
      let(:create_params) do
        {
          order_type: :one_off,
          billing_items: {
            "addOns" => [
              {
                "id" => add_on.id,
                "localId" => "3d08b2df-4e4c-4d58-b415-a525c1663735",
                "type" => "add_on",
                "payload" => {
                  "code" => add_on.code,
                  "units" => 1,
                  "unitAmountCents" => 10_000,
                  "totalAmountCents" => 10_000
                }
              }
            ]
          }
        }
      end

      it "creates the quote with its version" do
        expect(result).to be_success
        expect(result.quote.order_type).to eq("one_off")
        expect(result.quote.current_version.billing_items).to eq(create_params[:billing_items])
      end

      context "when the payload is invalid" do
        let(:create_params) do
          {
            order_type: :one_off,
            billing_items: {
              "addOns" => [{"id" => "not-a-uuid", "localId" => "l1", "type" => "add_on", "payload" => {}}]
            }
          }
        end

        it "returns a validation failure and persists nothing" do
          expect { result }.not_to change(Quote, :count)
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to eq({"billing_items.addOns.0.id": ["invalid_format"]})
        end
      end
    end

    context "when subscription is required and provided correctly", :premium do
      let(:plan) { create(:plan, organization:, amount_currency: "USD") }
      let(:subscription) { create(:subscription, organization:, customer:, plan:) }
      let(:create_params) do
        {
          billing_items: {},
          content: "Amendment",
          order_type: :subscription_amendment,
          owners: [owner.id]
        }
      end

      it "creates the quote linked to the subscription" do
        expect(result).to be_success
        expect(result.quote.subscription_id).to eq(subscription.id)
        expect(result.quote.order_type).to eq("subscription_amendment")
      end

      it "takes the currency from the subscription plan" do
        expect(customer.currency).to eq("EUR")
        expect(result.quote.current_version.currency).to eq("USD")
      end
    end

    context "when subscription belongs to another customer", :premium do
      let(:other_customer) { create(:customer, organization:) }
      let(:subscription) { create(:subscription, organization:, customer: other_customer) }
      let(:create_params) do
        {order_type: :subscription_amendment, owners: [owner.id]}
      end

      it "returns subscription_not_found" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("subscription_not_found")
      end
    end

    context "when subscription belongs to another organization", :premium do
      let(:other_organization) { create(:organization, feature_flags: ["order_forms"]) }
      let(:other_customer) { create(:customer, organization: other_organization) }
      let(:subscription) { create(:subscription, organization: other_organization, customer: other_customer) }
      let(:create_params) do
        {order_type: :subscription_amendment, owners: [owner.id]}
      end

      it "returns subscription_not_found" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("subscription_not_found")
      end
    end

    context "when the version creation fails with a non-validation failure", :premium do
      before do
        allow(QuoteVersions::CreateService).to receive(:call!)
          .and_raise(BaseService::ForbiddenFailure.new(BaseResult.new, code: "active_version_exists"))
      end

      it "surfaces the failure instead of letting it escape" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("active_version_exists")
      end

      it "rolls the quote back" do
        expect { result }.not_to change(Quote, :count)
      end
    end

    context "when owners include invalid user ids", :premium do
      let(:create_params) do
        {order_type: :subscription_creation, owners: ["invalid_user_id"]}
      end

      it "returns validation failure" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:owners]).to eq(["invalid"])
      end
    end

    context "when organization does not exist", :premium do
      let(:organization) { nil }
      let(:customer) { create(:customer) }
      let(:membership) { create(:membership) }

      it "returns a not found error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("organization_not_found")
      end
    end

    context "when customer does not exist", :premium do
      let(:customer) { nil }

      it "returns a not found error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("customer_not_found")
      end
    end

    context "when subscription is required but not provided", :premium do
      let(:create_params) { {order_type: "subscription_amendment"} }

      it "returns a not found error" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.message).to eq("subscription_not_found")
      end
    end

    context "when license is not premium" do
      it "returns forbidden status" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("feature_unavailable")
      end
    end

    context "when feature flag is disabled", :premium do
      let(:organization) { create(:organization) }

      it "returns forbidden status" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("feature_unavailable")
      end
    end
  end
end
